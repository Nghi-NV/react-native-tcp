using ReactNative.Bridge;
using System;
using System.Collections.Generic;
using Windows.ApplicationModel.Core;
using Windows.UI.Core;

namespace Tcp.Ssl.RNTcpSsl
{
    /// <summary>
    /// A module that allows JS to share data.
    /// </summary>
    class RNTcpSslModule : NativeModuleBase
    {
        /// <summary>
        /// Instantiates the <see cref="RNTcpSslModule"/>.
        /// </summary>
        internal RNTcpSslModule()
        {

        }

        /// <summary>
        /// The name of the native module.
        /// </summary>
        public override string Name
        {
            get
            {
                return "RNTcpSsl";
            }
        }
    }
}
