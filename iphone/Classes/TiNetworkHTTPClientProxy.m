/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2010 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */

#import "TiNetworkHTTPClientProxy.h"
#import "TiNetworkHTTPClientResultProxy.h"
#import "TiUtils.h"
#import "TitaniumApp.h"

int CaselessCompare(const char * firstString, const char * secondString, int size)
{
	int index = 0;
	while(index < size)
	{
		char firstChar = tolower(firstString[index]);
		char secondChar = secondString[index]; //Second string is always lowercase.
		index++;
		if(firstChar!=secondChar)return index; //Yes, this is one after the failure.
	}
	return 0;
}


#define TRYENCODING( encodingName, nameSize, returnValue )	\
if((remainingSize > nameSize) && (0==CaselessCompare(data, encodingName, nameSize))) return returnValue;

NSStringEncoding ExtractEncodingFromData(NSData * inputData)
{
	int remainingSize = [inputData length];
	int unsearchableSize;
	if(remainingSize > 2008) unsearchableSize = remainingSize - 2000;
	else unsearchableSize = 8; // So that there's no chance of overrunning the buffer with 'charset='
	const char * data = [inputData bytes];
	
	while(remainingSize > unsearchableSize)
	{
		int compareOffset = CaselessCompare(data, "charset=", 8);
		if (compareOffset != 0)
		{
			data += compareOffset;
			remainingSize -= compareOffset;
			continue;
		}
		data += 8;
		remainingSize -= 8;
		
		TRYENCODING("windows-1252",12,NSWindowsCP1252StringEncoding);
		TRYENCODING("iso-8859-1",10,NSISOLatin1StringEncoding);
		TRYENCODING("utf-8",5,NSUTF8StringEncoding);
		TRYENCODING("shift-jis",9,NSShiftJISStringEncoding);
		TRYENCODING("x-euc",5,NSJapaneseEUCStringEncoding);
		TRYENCODING("windows-1250",12,NSWindowsCP1251StringEncoding);
		TRYENCODING("windows-1251",12,NSWindowsCP1252StringEncoding);
		TRYENCODING("windows-1253",12,NSWindowsCP1253StringEncoding);
		TRYENCODING("windows-1254",12,NSWindowsCP1254StringEncoding);
	}	
	return NSUTF8StringEncoding;
}

@implementation TiNetworkHTTPClientProxy

@synthesize onload, onerror, onreadystatechange, ondatastream, onsendstream;

-(id)init
{
	if (self = [super init])
	{
		readyState = NetworkClientStateUnsent;
	}
	return self;
}

-(void)_destroy
{
	if (request!=nil && connected)
	{
		[request cancel];
	}
	RELEASE_TO_NIL(url);
	RELEASE_TO_NIL(onload);
	RELEASE_TO_NIL(onerror);
	RELEASE_TO_NIL(onreadystatechange);
	RELEASE_TO_NIL(ondatastream);
	RELEASE_TO_NIL(onsendstream);
	RELEASE_TO_NIL(request);
	[super _destroy];
}

-(id)description
{
	return @"[object TiNetworkClient]";
}

-(NSNumber*)status
{
	if (request!=nil)
	{
		return [NSNumber numberWithInt:[request responseStatusCode]];
	}
	else 
	{
		return [NSNumber numberWithInt:-1];
	}
}

-(NSNumber*)readyState
{
	return [NSNumber numberWithInt:readyState];
}

-(NSNumber*)connected
{
	return [NSNumber numberWithBool:connected];
}

-(NSString*)responseText
{
	if (request!=nil && [request error]==nil)
	{
		NSData *data = [request responseData];
		if (data==nil) 
		{
			return nil;
		}
		NSString * result = [[[NSString alloc] initWithBytes:[data bytes] length:[data length] encoding:[request responseEncoding]] autorelease];
		if (result==nil)
		{
			// encoding failed, probably a bad webserver or content we have to deal
			// with in a _special_ way
			NSStringEncoding encoding = ExtractEncodingFromData(data);
			result = [[[NSString alloc] initWithBytes:[data bytes] length:[data length] encoding:encoding] autorelease];
			if (result!=nil)
			{
				return result;
			}
		}
	}
	return nil;
}

-(NSString*)responseXML
{
	if (request!=nil && [request error]==nil)
	{
		//TODO
	}
	return nil;
}

-(TiBlob*)responseData
{
	if (request!=nil && [request error]==nil)
	{
		NSString *contentType = [[request responseHeaders] objectForKey:@"Content-Type"];
		return [[[TiBlob alloc] initWithData:[request responseData] mimetype:contentType] autorelease];
	}
	return nil;
}

-(NSString*)connectionType
{
	//get or post
	return [request requestMethod];
}

-(NSString*)location
{
	return [[request url] absoluteString];
}

-(NSNumber*)UNSENT
{
	return [NSNumber numberWithInt:NetworkClientStateUnsent];
}

-(NSNumber*)OPENED
{
	return [NSNumber numberWithInt:NetworkClientStateOpened];
}

-(NSNumber*)HEADERS_RECEIVED
{
	return [NSNumber numberWithInt:NetworkClientStateHeaders];
}

-(NSNumber*)LOADING
{
	return [NSNumber numberWithInt:NetworkClientStateLoading];
}

-(NSNumber*)DONE
{
	return [NSNumber numberWithInt:NetworkClientStateDone];
}

-(void)_fireReadyStateChange:(NetworkClientState) state
{
	readyState = state;
	TiNetworkHTTPClientResultProxy *thisPointer = [[[TiNetworkHTTPClientResultProxy alloc] initWithDelegate:self] autorelease];
	if (onreadystatechange!=nil)
	{
		[self _fireEventToListener:@"readystatechange" withObject:nil listener:onreadystatechange thisObject:thisPointer];
	}
	if (onload!=nil && state==NetworkClientStateDone)
	{
		[self _fireEventToListener:@"load" withObject:nil listener:onload thisObject:thisPointer];
	}
}

-(void)abort
{
	if (request!=nil && connected)
	{
		connected = NO;
		[[TitaniumApp app] stopNetwork];
		[request cancel];
	}
}

-(void)open:(id)args
{
	RELEASE_TO_NIL(request);
	
	NSString *method = [TiUtils stringValue:[args objectAtIndex:0]];
	url = [[TiUtils toURL:[args objectAtIndex:1] proxy:self] retain];
	
	if ([args count]>2)
	{
		async = [TiUtils boolValue:[args objectAtIndex:2]];
	}
	else 
	{
		async = YES;
	}
	
	request = [[ASIFormDataRequest requestWithURL:url] retain];	
	[request setDelegate:self];
	
	if (onsendstream!=nil)
	{
		[request setUploadProgressDelegate:self];
	}
	if (ondatastream!=nil)
	{
		[request setDownloadProgressDelegate:self];
	}
	
	//TODO: setup useragent, etc
	[request addRequestHeader:@"User-Agent" value:[[TitaniumApp app] userAgent]];
	[request setRequestMethod:method];
	[request setDefaultResponseEncoding:NSUTF8StringEncoding];
	[self _fireReadyStateChange:NetworkClientStateOpened];
	[self _fireReadyStateChange:NetworkClientStateHeaders];
}

-(void)setRequestHeader:(id)args
{
	ENSURE_ARG_COUNT(args,2);
	
	NSString *key = [TiUtils stringValue:[args objectAtIndex:0]];
	NSString *value = [TiUtils stringValue:[args objectAtIndex:1]];
	[request addRequestHeader:key value:value];
}

-(void)setTimeout:(id)args
{
	double timeout = [[args objectAtIndex:0] doubleValue] / 1000;
	[request setTimeOutSeconds:timeout];
}

-(void)send:(id)args
{
	// args are optional
	if (args!=nil)
	{
		for (id arg in args)
		{
			if ([arg isKindOfClass:[NSString class]])
			{
				//body of request
				[request appendPostData:[arg dataUsingEncoding:NSUTF8StringEncoding]];
			}
			else if ([arg isKindOfClass:[NSDictionary class]])
			{
				for (id key in arg)
				{
					id value = [arg objectForKey:key];
					if ([value isKindOfClass:[TiBlob class]])
					{
						TiBlob *blob = (TiBlob*)value;
						if ([blob type] == TiBlobTypeFile)
						{
							// could be large if file so let's tell the 
							// ASI request dude to stream the content
							NSString *filename = [[blob path] lastPathComponent];
							[request setFile:[blob path] withFileName:filename andContentType:[blob mimeType] forKey:key];
						}
						else
						{
							NSData *data = [blob data];
							[request setData:data forKey:(NSString*)key];
						}
					}
					else
					{
						value = [TiUtils stringValue:value];
						[request setPostValue:(NSString*)value forKey:(NSString*)key];
					}
				}
			}
			else if ([arg isKindOfClass:[TiBlob class]])
			{
				TiBlob *blob = (TiBlob*)arg;
				if ([blob type] == TiBlobTypeFile)
				{
					// could be large if file so let's tell the 
					// ASI request dude to stream the content
					[request appendPostDataFromFile:[blob path]];
				}
				else
				{
					NSData *data = [blob data];
					[request appendPostData:data];
				}
			}
		}
	}
	
	connected = YES;
	downloadProgress = -1;
	uploadProgress = -1;
	[[TitaniumApp app] startNetwork];
	[self _fireReadyStateChange:NetworkClientStateLoading];
	[request setAllowCompressedResponse:YES];
	
	if (async)
	{
		[request startAsynchronous];
	}
	else
	{
		[[TitaniumApp app] startNetwork];
		[request start];
		[[TitaniumApp app] stopNetwork];
	}
}

-(id)getResponseHeader:(id)args
{
	if (request!=nil)
	{
		id key = [args objectAtIndex:0];
		ENSURE_TYPE(key,NSString);
		return [[request responseHeaders] objectForKey:key];
	}
	return nil;
}

#pragma mark Delegates

-(void)requestFinished:(ASIHTTPRequest *)request_
{
	[self _fireReadyStateChange:NetworkClientStateDone];
	if (connected)
	{
		connected = NO;
		[[TitaniumApp app] stopNetwork];
	}
}

-(void)requestFailed:(ASIHTTPRequest *)request_
{
	if (connected)
	{
		[[TitaniumApp app] stopNetwork];
		connected=NO;
	}
	
	NSError *error = [request error];
	
	[self _fireReadyStateChange:NetworkClientStateDone];
	
	if (onerror!=nil)
	{
		TiNetworkHTTPClientResultProxy *thisPointer = [[[TiNetworkHTTPClientResultProxy alloc] initWithDelegate:self] autorelease];
		NSDictionary *event = [NSDictionary dictionaryWithObject:[error description] forKey:@"error"];
		[self _fireEventToListener:@"error" withObject:event listener:onerror thisObject:thisPointer];
	}
}

-(void)setProgress:(float)value upload:(BOOL)upload
{
	if (upload)
	{
		if (uploadProgress==value)
		{
			return;
		}
		uploadProgress = value;
	}
	else
	{
		if (downloadProgress==value)
		{
			return;
		}
		downloadProgress = value;
	}	
	
	TiNetworkHTTPClientResultProxy *thisPointer = [[[TiNetworkHTTPClientResultProxy alloc] initWithDelegate:self] autorelease];
	
	NSDictionary *event = [NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:value] forKey:@"progress"];
	
	if (upload)
	{
		[self _fireEventToListener:@"sendstream" withObject:event listener:onsendstream thisObject:thisPointer];
	}
	else
	{
		[self _fireEventToListener:@"datastream" withObject:event listener:ondatastream thisObject:thisPointer];
	}
}

@end
