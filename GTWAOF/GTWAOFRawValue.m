//
//  GTWAOFRawValue.m
//  GTWAOF
//
//  Created by Gregory Williams on 12/16/13.
//  Copyright (c) 2013 Gregory Todd Williams. All rights reserved.
//

/**
 4  cookie              [RVAL]
 4  padding
 8  timestamp           (seconds since epoch)
 8  prev_page_id
 8	(vl) value length	(the number of quads in this page, stored as a big-endian integer)
 vl	value bytes
 */
#import "GTWAOFRawValue.h"
#import "GTWAOFUpdateContext.h"

#define TS_OFFSET       8
#define PREV_OFFSET     16
#define LENGTH_OFFSET   24
#define DATA_OFFSET     32

@implementation GTWAOFRawValue

+ (GTWAOFRawValue*) valueWithData:(NSData*) data aof:(id<GTWAOF>)_aof {
    NSMutableData* d   = [data mutableCopy];
    __block GTWAOFPage* page;
    BOOL ok = [_aof updateWithBlock:^BOOL(GTWAOFUpdateContext *ctx) {
        int64_t prev  = -1;
        if ([d length]) {
            while ([d length]) {
                NSData* pageData    = newValueData([_aof pageSize], d, prev, NO);
                if(!pageData)
                    return NO;
                page    = [ctx createPageWithData:pageData];
                prev    = page.pageID;
            }
        } else {
            NSData* empty   = emptyValueData([_aof pageSize], prev, NO);
            page            = [ctx createPageWithData:empty];
        }
        return YES;
    }];
    if (!ok)
        return nil;
    //    NSLog(@"new quads head: %@", page);
    return [[GTWAOFRawValue alloc] initWithPage:page fromAOF:_aof];
}

- (void) _loadData {
    NSMutableData* data = [NSMutableData data];
    if ([self previousPageID] >= 0) {
        GTWAOFRawValue* prev    = [self previousPage];
        [data appendData: [prev data]];
    }
    
    GTWAOFPage* p   = _head;
    uint64_t big_length = 0;
    [p.data getBytes:&big_length range:NSMakeRange(LENGTH_OFFSET, 8)];
    unsigned long long length = NSSwapBigLongLongToHost((unsigned long long) big_length);
    
    NSData* pageData    = [p.data subdataWithRange: NSMakeRange(DATA_OFFSET, length)];
    [data appendData: pageData];
    self.data   = [data copy];
}

- (GTWAOFRawValue*) initWithPageID:(NSInteger)pageID fromAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof    = aof;
        _head   = [aof readPage:pageID];
        [self _loadData];
    }
    return self;
}

- (GTWAOFRawValue*) initWithPage:(GTWAOFPage*)page fromAOF:(id<GTWAOF>)aof {
    if (self = [self init]) {
        _aof    = aof;
        _head   = page;
        [self _loadData];
    }
    return self;
}

- (NSInteger) pageID {
    return _head.pageID;
}

- (NSInteger) previousPageID {
    GTWAOFPage* p   = _head;
    NSData* data    = p.data;
    uint64_t big_prev = 0;
    [data getBytes:&big_prev range:NSMakeRange(PREV_OFFSET, 8)];
    unsigned long long prev = NSSwapBigLongLongToHost((unsigned long long) big_prev);
    return (NSInteger) prev;
}

- (GTWAOFRawValue*) previousPage {
    GTWAOFRawValue* prev   = [[GTWAOFRawValue alloc] initWithPageID:self.previousPageID fromAOF:_aof];
    return prev;
}

- (GTWAOFPage*) head {
    return _head;
}

- (NSDate*) lastModified {
    GTWAOFPage* p   = _head;
    NSData* data    = p.data;
    uint64_t big_ts = 0;
    [data getBytes:&big_ts range:NSMakeRange(TS_OFFSET, 8)];
    unsigned long long ts = NSSwapBigLongLongToHost((unsigned long long) big_ts);
    return [NSDate dateWithTimeIntervalSince1970:(double)ts];
}

- (NSUInteger) length {
    return [self.data length];
}

- (NSUInteger) pageLength {
    GTWAOFPage* p   = _head;
    NSData* data    = p.data;
    uint64_t big_length = 0;
    [data getBytes:&big_length range:NSMakeRange(LENGTH_OFFSET, 8)];
    unsigned long long length = NSSwapBigLongLongToHost((unsigned long long) big_length);
    return (NSUInteger) length;
}

//+ (void)enumerateObjectsForPage:(NSInteger) pageID fromAOF:(id<GTWAOF>)aof usingBlock:(void (^)(NSData* key, NSRange range, NSUInteger idx, BOOL *stop))block followTail:(BOOL)follow {
//    @autoreleasepool {
//        while (pageID >= 0) {
//            GTWAOFRawQuads* q  = [[GTWAOFRawQuads alloc] initWithPageID:pageID fromAOF:aof];
//            //            NSLog(@"Quads Page: %lu", q.pageID);
//            //            NSLog(@"Quads Page Last-Modified: %@", [q lastModified]);
//            GTWAOFPage* p   = q.head;
//            NSData* data    = p.data;
//            int64_t big_prev_page_id    = -1;
//            [data getBytes:&big_prev_page_id range:NSMakeRange(PREV_OFFSET, 8)];
//            long long prev_page_id = NSSwapBigLongLongToHost(big_prev_page_id);
//            //            NSLog(@"Quads Previous Page: %"PRId64, prev_page_id);
//            
//            NSUInteger count    = [q count];
//            NSUInteger i;
//            BOOL stop   = NO;
//            for (i = 0; i < count; i++) {
//                NSRange range   = [self rangeOfObjectAtIndex:i];
//                block(q.head.data, range, i, &stop);
//                if (stop)
//                    break;
//            }
//            
//            pageID  = prev_page_id;
//            if (!follow)
//                break;
//        }
//    }
//}

NSMutableData* emptyValueData( NSUInteger pageSize, int64_t prevPageID, BOOL verbose ) {
    uint64_t ts     = (uint64_t) [[NSDate date] timeIntervalSince1970];
    int64_t prev    = (int64_t) prevPageID;
    if (verbose) {
        NSLog(@"creating quads page data with previous page ID: %lld (%lld)", prevPageID, prev);
    }
    uint64_t bigts  = NSSwapHostLongLongToBig(ts);
    int64_t bigprev = NSSwapHostLongLongToBig(prev);
    
    int64_t biglength    = 0;
    
    NSMutableData* data = [NSMutableData dataWithLength:pageSize];
    [data replaceBytesInRange:NSMakeRange(0, 4) withBytes:RAW_VALUE_COOKIE];
    [data replaceBytesInRange:NSMakeRange(TS_OFFSET, 8) withBytes:&bigts];
    [data replaceBytesInRange:NSMakeRange(PREV_OFFSET, 8) withBytes:&bigprev];
    [data replaceBytesInRange:NSMakeRange(LENGTH_OFFSET, 8) withBytes:&biglength];
    return data;
}

NSData* newValueData( NSUInteger pageSize, NSMutableData* value, int64_t prevPageID, BOOL verbose ) {
    int64_t max     = pageSize - DATA_OFFSET;
    int64_t vlength = [value length];
    int64_t length  = (max < vlength) ? max : vlength;
    int64_t biglength    = NSSwapHostLongLongToBig(length);
    
    NSMutableData* data = emptyValueData(pageSize, prevPageID, verbose);
    [data replaceBytesInRange:NSMakeRange(LENGTH_OFFSET, 8) withBytes:&biglength];
    __block int offset  = DATA_OFFSET;
//    NSUInteger i;
    
    const char* bytes   = [value bytes];
    [data replaceBytesInRange:NSMakeRange(offset, length) withBytes:bytes];
    NSData* tail    = [value subdataWithRange:NSMakeRange(length, [value length]-length)];
    [value setData:tail];
    NSLog(@"New length of value data is %llu", (unsigned long long) [value length]);
    if ([data length] != pageSize) {
        NSLog(@"page has bad size for value");
        return nil;
    }
    return data;
}

@end
