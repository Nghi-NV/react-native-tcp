package com.peel.react;

import android.support.annotation.Nullable;
import android.util.SparseArray;
import com.facebook.react.bridge.ReactApplicationContext;

import com.koushikdutta.async.AsyncSSLSocket;
import com.koushikdutta.async.AsyncSSLSocketWrapper;


import javax.net.ssl.HostnameVerifier;
import javax.net.ssl.SSLSession;


import com.koushikdutta.async.AsyncNetworkSocket;
import com.koushikdutta.async.AsyncServer;
import com.koushikdutta.async.AsyncServerSocket;
import com.koushikdutta.async.AsyncSocket;
import com.koushikdutta.async.ByteBufferList;
import com.koushikdutta.async.DataEmitter;
import com.koushikdutta.async.Util;
import com.koushikdutta.async.callback.CompletedCallback;
import com.koushikdutta.async.callback.ConnectCallback;
import com.koushikdutta.async.callback.DataCallback;
import com.koushikdutta.async.callback.ListenCallback;

import java.io.IOException;
import java.lang.ref.WeakReference;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.UnknownHostException;



import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableMap;

import java.security.KeyStore;
import java.security.cert.X509Certificate;

import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLEngine;
import javax.net.ssl.TrustManager;
import javax.net.ssl.TrustManagerFactory;
import javax.net.ssl.X509TrustManager;
import 	java.io.InputStream;

/**
 * Created by aprock on 12/29/15.
 */
public final class TcpSocketManager {
    private SparseArray<Object> mClients = new SparseArray<Object>();

    private WeakReference<TcpSocketListener> mListener;
    private AsyncServer mServer = AsyncServer.getDefault();

    private int mInstances = 5000;
    ReactApplicationContext context;
    public TcpSocketManager(TcpSocketListener listener, ReactApplicationContext c) throws IOException {
        mListener = new WeakReference<TcpSocketListener>(listener);
        context = c;
    }

    private void setSocketCallbacks(final Integer cId, final AsyncSocket socket) {
        socket.setClosedCallback(new CompletedCallback() {
            @Override
            public void onCompleted(Exception ex) {
                TcpSocketListener listener = mListener.get();
                if (listener != null) {
                    listener.onClose(cId, ex==null?null:ex.getMessage());
                }
            }
        });

        socket.setDataCallback(new DataCallback() {
            @Override
            public void onDataAvailable(DataEmitter emitter, ByteBufferList bb) {
                TcpSocketListener listener = mListener.get();
                if (listener != null) {
                    listener.onData(cId, bb.getAllByteArray());
                }
            }
        });

        socket.setEndCallback(new CompletedCallback() {
            @Override
            public void onCompleted(Exception ex) {
                if (ex != null) {
                    TcpSocketListener listener = mListener.get();
                    if (listener != null) {
                        listener.onError(cId, ex.getMessage());
                    }
                }
                socket.close();
            }
        });
    }

    public void listen(final Integer cId, final String host, final Integer port) throws UnknownHostException, IOException {
        // resolve the address
        final InetSocketAddress socketAddress;
        if (host != null) {
            socketAddress = new InetSocketAddress(InetAddress.getByName(host), port);
        } else {
            socketAddress = new InetSocketAddress(port);
        }

        mServer.listen(InetAddress.getByName(host), port, new ListenCallback() {
            @Override
            public void onListening(AsyncServerSocket socket) {
                mClients.put(cId, socket);

                TcpSocketListener listener = mListener.get();
                if (listener != null) {
                    listener.onConnect(cId, socketAddress);
                }
            }

            @Override
            public void onAccepted(AsyncSocket socket) {
                setSocketCallbacks(mInstances, socket);
                mClients.put(mInstances, socket);

                AsyncNetworkSocket socketConverted = Util.getWrappedSocket(socket, AsyncNetworkSocket.class);
                InetSocketAddress remoteAddress = socketConverted != null ? socketConverted.getRemoteAddress() : socketAddress;

                TcpSocketListener listener = mListener.get();
                if (listener != null) {
                    listener.onConnection(cId, mInstances, remoteAddress);
                }

                mInstances++;
            }

            @Override
            public void onCompleted(Exception ex) {
                mClients.delete(cId);

                TcpSocketListener listener = mListener.get();
                if (listener != null) {
                    listener.onClose(cId, ex != null ? ex.getMessage() : null);
                }
            }
        });
    }

    public void connect(final Integer cId, final @Nullable String host, final Integer port, final ReadableMap options) throws UnknownHostException, IOException {
        // resolve the address
        final InetSocketAddress socketAddress;
        if (host != null) {
            socketAddress = new InetSocketAddress(InetAddress.getByName(host), port);
        } else {
            socketAddress = new InetSocketAddress(port);
        }
        final String cert;
        final String certificatePassword;
        final String keyStorePassword;
        if(options != null)
        {

            cert = options.hasKey("cert") ? options.getString("cert") : null;
            certificatePassword = options.hasKey("pass") ? options.getString("pass") : null;
            keyStorePassword = options.hasKey("passkeystore") ? options.getString("passkeystore") : null;
        }else
        {
            cert = null;
            certificatePassword = null;
            keyStorePassword = null;
        }

        mServer.connectSocket(socketAddress, new ConnectCallback() {
            @Override
            public void onConnectCompleted(Exception ex, AsyncSocket socket) {

                if(cert != null)
                {
                     try
                    {
                        SSLContext sslContext = SSLContext.getInstance("TLS");
                    KeyStore ks = KeyStore.getInstance(KeyStore.getDefaultType());

                    InputStream is = context.getResources().openRawResource(R.raw.lumi);
                    ks.load(is, keyStorePassword.toCharArray());
                    // ks.load(SecureSocketKeyStore.asInputStream(),
                    //         SecureSocketKeyStore.getKeyStorePassword());

                    // Set up key manager factory to use our key store
                    String algorithm = TrustManagerFactory.getDefaultAlgorithm();
                    KeyManagerFactory kmf = KeyManagerFactory.getInstance(algorithm);
                    kmf.init(ks, certificatePassword.toCharArray());

                    TrustManager[] trustAllCerts = new TrustManager[] { new X509TrustManager() {
                        public java.security.cert.X509Certificate[] getAcceptedIssuers() {
                            return new X509Certificate[0];
                        }

                        public void checkClientTrusted(java.security.cert.X509Certificate[] certs, String authType) {
                        }

                        public void checkServerTrusted(java.security.cert.X509Certificate[] certs, String authType) {

                        }
                    } };
                    sslContext.init(kmf.getKeyManagers(), trustAllCerts, null);

                    AsyncSSLSocketWrapper.handshake(socket, host, port,  sslContext.createSSLEngine(),
                            trustAllCerts, new HostnameVerifier()
                            {
                                @Override
                                public boolean verify(String hostname, SSLSession session) {
                                    return true;
                                }
                            }, true,
                            new AsyncSSLSocketWrapper.HandshakeCallback() {
                                @Override
                                public void onHandshakeCompleted(Exception e, AsyncSSLSocket s) {
                                    TcpSocketListener listener = mListener.get();
                                    if (e == null) {
                                        mClients.put(cId, s);
                                        setSocketCallbacks(cId, s);

                                        if (listener != null) {
                                            listener.onConnect(cId, socketAddress);
                                        }
                                    } else if (listener != null) {
                                        listener.onError(cId, e.getMessage());
                                    }
                                }
                            });
                    }catch (Exception e)
                    {
                        TcpSocketListener listener = mListener.get();
                        if (listener != null) {
                            listener.onError(cId, e.getMessage());
                        }
                    }
                    
                }else
                {
                    TcpSocketListener listener = mListener.get();
                    if (ex == null) {
                        mClients.put(cId, socket);
                        setSocketCallbacks(cId, socket);

                        if (listener != null) {
                            listener.onConnect(cId, socketAddress);
                        }
                    } else if (listener != null) {
                        listener.onError(cId, ex.getMessage());
                    }
                }              
            }
        });
    }

    public void write(final Integer cId, final byte[] data) {
        Object socket = mClients.get(cId);
        if (socket != null && socket instanceof AsyncSocket) {
            ((AsyncSocket) socket).write(new ByteBufferList(data));
        }
    }

    public void close(final Integer cId) {
        Object socket = mClients.get(cId);
        if (socket != null) {
            if (socket instanceof AsyncSocket) {
                ((AsyncSocket) socket).close();
            } else if (socket instanceof AsyncServerSocket) {
                ((AsyncServerSocket) socket).stop();
            }
        } else {
            TcpSocketListener listener = mListener.get();
            if (listener != null) {
               listener.onError(cId, "unable to find socket");
            }
        }
    }

    public void closeAllSockets() {
        for (int i = 0; i < mClients.size(); i++) {
            close(mClients.keyAt(i));
        }
        mClients.clear();
    }
}
