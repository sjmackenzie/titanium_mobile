/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */

#import "SocketModule.h"
#import "TiBase.h"
#import "TiTCPSocketProxy.h"

@implementation SocketModule

-(NSNumber*)READ_MODE
{
    return [NSNumber numberWithInt:READ_MODE];
}

-(NSNumber*)WRITE_MODE
{
    return [NSNumber numberWithInt:WRITE_MODE];
}

-(NSNumber*)READ_WRITE_MODE
{
    return [NSNumber numberWithInt:READ_WRITE_MODE];
}

@end