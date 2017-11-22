/**
 * Copyright (c) 2015-present, Peel Technologies, Inc.
 * All rights reserved.
 */

#import <netinet/in.h>
#import <arpa/inet.h>
#import "TcpSocketClient.h"

#import <React/RCTLog.h>

NSString *const RCTTCPErrorDomain = @"RCTTCPErrorDomain";

@interface TcpSocketClient()
{
@private
    GCDAsyncSocket *_tcpSocket;
    NSMutableDictionary<NSNumber *, RCTResponseSenderBlock> *_pendingSends;
    NSLock *_lock;
    long _sendTag;
}

- (id)initWithClientId:(NSNumber *)clientID andConfig:(id<SocketClientDelegate>)aDelegate;
- (id)initWithClientId:(NSNumber *)clientID andConfig:(id<SocketClientDelegate>)aDelegate andSocket:(GCDAsyncSocket*)tcpSocket;

@end

@implementation TcpSocketClient

+ (id)socketClientWithId:(nonnull NSNumber *)clientID andConfig:(id<SocketClientDelegate>)delegate
{
    return [[[self class] alloc] initWithClientId:clientID andConfig:delegate andSocket:nil];
}

- (id)initWithClientId:(NSNumber *)clientID andConfig:(id<SocketClientDelegate>)aDelegate
{
    return [self initWithClientId:clientID andConfig:aDelegate andSocket:nil];
}

- (id)initWithClientId:(NSNumber *)clientID andConfig:(id<SocketClientDelegate>)aDelegate andSocket:(GCDAsyncSocket*)tcpSocket;
{
    self = [super init];
    if (self) {
        
        _isSecure = false;
        _nameFilePKCS12 = @"";
        _passwordFilePKCS12 = @"";
        _id = clientID;
        _clientDelegate = aDelegate;
        _pendingSends = [NSMutableDictionary dictionary];
        _lock = [[NSLock alloc] init];
        _tcpSocket = tcpSocket;
        [_tcpSocket setUserData: clientID];
    }
    return self;
}

- (BOOL)connect:(NSString *)host port:(int)port withOptions:(NSDictionary *)options error:(NSError **)error
{
    if (_tcpSocket) {
        if (error) {
            *error = [self badInvocationError:@"this client's socket is already connected"];
        }

        return false;
    }
    
    _nameFilePKCS12 = (options?options[@"cert"] : nil);
    _passwordFilePKCS12 = (options?options[@"pass"] : nil);
    if(_nameFilePKCS12 && _passwordFilePKCS12)
    {
        _isSecure = true;
    }
    

    _tcpSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:[self methodQueue]];
    [_tcpSocket setUserData: _id];

    BOOL result = false;

    NSString *localAddress = (options?options[@"localAddress"]:nil);
    NSNumber *localPort = (options?options[@"localPort"]:nil);

    if (!localAddress && !localPort) {
        result = [_tcpSocket connectToHost:host onPort:port error:error];
    } else {
        NSMutableArray *interface = [NSMutableArray arrayWithCapacity:2];
        [interface addObject: localAddress?localAddress:@""];
        if (localPort) {
            [interface addObject:[localPort stringValue]];
        }
        result = [_tcpSocket connectToHost:host
                                    onPort:port
                              viaInterface:[interface componentsJoinedByString:@":"]
                               withTimeout:-1
                                     error:error];
    }

    return result;
}

- (NSDictionary<NSString *, id> *)getAddress
{
    if (_tcpSocket)
    {
        if (_tcpSocket.isConnected) {
            return @{ @"port": @(_tcpSocket.connectedPort),
                      @"address": _tcpSocket.connectedHost ?: @"unknown",
                      @"family": _tcpSocket.isIPv6?@"IPv6":@"IPv4" };
        } else {
            return @{ @"port": @(_tcpSocket.localPort),
                      @"address": _tcpSocket.localHost ?: @"unknown",
                      @"family": _tcpSocket.isIPv6?@"IPv6":@"IPv4" };
        }
    }

    return @{ @"port": @(0),
              @"address": @"unknown",
              @"family": @"unkown" };
}

- (BOOL)listen:(NSString *)host port:(int)port error:(NSError **)error
{
    if (_tcpSocket) {
        if (error) {
            *error = [self badInvocationError:@"this client's socket is already connected"];
        }

        return false;
    }

    _tcpSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:[self methodQueue]];
    [_tcpSocket setUserData: _id];

    // GCDAsyncSocket doesn't recognize 0.0.0.0
    if ([@"0.0.0.0" isEqualToString: host]) {
        host = @"localhost";
    }
    BOOL isListening = [_tcpSocket acceptOnInterface:host port:port error:error];
    if (isListening == YES) {
        [_clientDelegate onConnect: self];
        [_tcpSocket readDataWithTimeout:-1 tag:_id.longValue];
    }

    return isListening;
}

- (void)setPendingSend:(RCTResponseSenderBlock)callback forKey:(NSNumber *)key
{
    [_lock lock];
    @try {
        [_pendingSends setObject:callback forKey:key];
    }
    @finally {
        [_lock unlock];
    }
}

- (RCTResponseSenderBlock)getPendingSend:(NSNumber *)key
{
    [_lock lock];
    @try {
        return [_pendingSends objectForKey:key];
    }
    @finally {
        [_lock unlock];
    }
}

- (void)dropPendingSend:(NSNumber *)key
{
    [_lock lock];
    @try {
        [_pendingSends removeObjectForKey:key];
    }
    @finally {
        [_lock unlock];
    }
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)msgTag
{
    NSNumber* tagNum = [NSNumber numberWithLong:msgTag];
    RCTResponseSenderBlock callback = [self getPendingSend:tagNum];
    if (callback) {
        callback(@[]);
        [self dropPendingSend:tagNum];
    }
}

- (void) writeData:(NSData *)data
          callback:(RCTResponseSenderBlock)callback
{
    if (callback) {
        [self setPendingSend:callback forKey:@(_sendTag)];
    }
    [_tcpSocket writeData:data withTimeout:-1 tag:_sendTag];

    _sendTag++;

    [_tcpSocket readDataWithTimeout:-1 tag:_id.longValue];
}

- (void)end
{
    [_tcpSocket disconnectAfterWriting];
}

- (void)destroy
{
    [_tcpSocket disconnect];
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    if (!_clientDelegate) {
        RCTLogWarn(@"didReadData with nil clientDelegate for %@", [sock userData]);
        return;
    }

    [_clientDelegate onData:@(tag) data:data];

    [sock readDataWithTimeout:-1 tag:tag];
}

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
    TcpSocketClient *inComing = [[TcpSocketClient alloc] initWithClientId:[_clientDelegate getNextId]
                                                                andConfig:_clientDelegate
                                                                andSocket:newSocket];
    [_clientDelegate onConnection: inComing
                         toClient: _id];
    [newSocket readDataWithTimeout:-1 tag:inComing.id.longValue];
}

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port
{
    if (!_clientDelegate) {
        RCTLogWarn(@"didConnectToHost with nil clientDelegate for %@", [sock userData]);
        return;
    }
    if([self isSecure])
        [self secureSocket:sock];
    else
        [_clientDelegate onConnect:self];
    
    [sock readDataWithTimeout:-1 tag:_id.longValue];
}


- (void)secureSocket: (GCDAsyncSocket *)sock {
    SecIdentityRef identityRef = nil;
    NSString *identityPath = [[NSBundle mainBundle] pathForResource:[self nameFilePKCS12] ofType:@"p12"];
    NSData *PKCS12Data = [NSData dataWithContentsOfFile:identityPath];
    CFDataRef inPKCS12Data = (__bridge CFDataRef)PKCS12Data;
    
    
    CFStringRef password = (__bridge CFStringRef)[self passwordFilePKCS12];//CFSTR(pass);//CFSTR("test");
    const void *keys[] = { kSecImportExportPassphrase };
    
    const void *values[] = { password };
    CFDictionaryRef options = CFDictionaryCreate(NULL, keys, values, 1, NULL, NULL);
    CFArrayRef items = CFArrayCreate(NULL, 0, 0, NULL);
    OSStatus securityError = SecPKCS12Import(inPKCS12Data, options, &items);
    CFRelease(options);
    CFRelease(password);
    if (securityError == errSecSuccess) {
        NSLog(@"Success opening p12 KaliTouch certificate. Items: %ld", CFArrayGetCount(items));
        CFDictionaryRef identityDict = CFArrayGetValueAtIndex(items, 0);
        identityRef = (SecIdentityRef)CFDictionaryGetValue(identityDict, kSecImportItemIdentity);
    } else {
        NSLog(@"Error opening Certificate.");
    }
    
    
    SecIdentityRef  certArray[1] = { identityRef };
    CFArrayRef myCerts = CFArrayCreate(NULL, (void *)certArray, 1, NULL);
    
    //    NSArray *certs = [[NSArray alloc] initWithObjects:(__bridge id)identityRef, nil];
    
    
    NSMutableDictionary *setting = [NSMutableDictionary dictionary];
    [setting setObject:@NO forKey:GCDAsyncSocketSSLIsServer];
    
    
    [setting setObject:[NSNumber numberWithInteger:8] forKey:GCDAsyncSocketSSLProtocolVersionMin];
    [setting setObject:[NSNumber numberWithInteger:8] forKey:GCDAsyncSocketSSLProtocolVersionMax];
    
    
    [setting setObject:@YES forKey:GCDAsyncSocketManuallyEvaluateTrust];
    [setting setObject:(id)CFBridgingRelease(myCerts) forKey:GCDAsyncSocketSSLCertificates];
    
    
    [sock startTLS:setting];
}

- (void)socket:(GCDAsyncSocket *)sock didReceiveTrust:(SecTrustRef)trust completionHandler:(void (^)(BOOL shouldTrustPeer))completionHandler {
    NSLog(@"didReceiveTrust");
    if (completionHandler) completionHandler(YES);
}

- (void)socketDidSecure:(GCDAsyncSocket *)sock {
    // start receiving messages
    NSLog(@"socketDidSecure = %@", sock);
    
    [_clientDelegate onConnect:self];
}


- (void)socketDidCloseReadStream:(GCDAsyncSocket *)sock
{
    // TODO : investigate for half-closed sockets
    // for now close the stream completely
    [sock disconnect];
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
    if (!_clientDelegate) {
        RCTLogWarn(@"socketDidDisconnect with nil clientDelegate for %@", [sock userData]);
        return;
    }

    [_clientDelegate onClose:[sock userData] withError:(!err || err.code == GCDAsyncSocketClosedError ? nil : err)];
}

- (NSError *)badInvocationError:(NSString *)errMsg
{
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];

    return [NSError errorWithDomain:RCTTCPErrorDomain
                               code:RCTTCPInvalidInvocationError
                           userInfo:userInfo];
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

@end
