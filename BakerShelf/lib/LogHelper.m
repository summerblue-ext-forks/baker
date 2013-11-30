//
//  LogHelper.m
//  Baker
//
//  Created by CharlieJade on 11/30/13.
//
//

#import "LogHelper.h"


/**
 *  一个更好的 LogBaker 替换, 去掉 LogBaker 前面的那些 "2013-11-30 08:09:58.653 Baker[70599:a0b]"...
 *  用法: 把它当 LogBaker 来用就行了.
 */

void BetterNSLog (NSString *format, ...) {
    va_list argList;
    va_start (argList, format);
    NSString *message = [[[NSString alloc] initWithFormat: format arguments: argList] autorelease]; // remove autorelease for ARC
    fprintf (stderr, "%s\n---------------------------------//\n", [message UTF8String]);
    va_end  (argList);
}
