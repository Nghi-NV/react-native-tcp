
# react-native-tcp-ssl

## Getting started

`$ npm install react-native-tcp-ssl --save`

### Mostly automatic installation

`$ react-native link react-native-tcp-ssl`

### Manual installation


#### iOS

1. In XCode, in the project navigator, right click `Libraries` ➜ `Add Files to [your project's name]`
2. Go to `node_modules` ➜ `react-native-tcp-ssl` and add `RNTcpSsl.xcodeproj`
3. In XCode, in the project navigator, select your project. Add `libRNTcpSsl.a` to your project's `Build Phases` ➜ `Link Binary With Libraries`
4. Run your project (`Cmd+R`)<

#### Android

1. Open up `android/app/src/main/java/[...]/MainActivity.java`
  - Add `import com.reactlibrary.RNTcpSslPackage;` to the imports at the top of the file
  - Add `new RNTcpSslPackage()` to the list returned by the `getPackages()` method
2. Append the following lines to `android/settings.gradle`:
  	```
  	include ':react-native-tcp-ssl'
  	project(':react-native-tcp-ssl').projectDir = new File(rootProject.projectDir, 	'../node_modules/react-native-tcp-ssl/android')
  	```
3. Insert the following lines inside the dependencies block in `android/app/build.gradle`:
  	```
      compile project(':react-native-tcp-ssl')
  	```

#### Windows
[Read it! :D](https://github.com/ReactWindows/react-native)

1. In Visual Studio add the `RNTcpSsl.sln` in `node_modules/react-native-tcp-ssl/windows/RNTcpSsl.sln` folder to their solution, reference from their app.
2. Open up your `MainPage.cs` app
  - Add `using Tcp.Ssl.RNTcpSsl;` to the usings at the top of the file
  - Add `new RNTcpSslPackage()` to the `List<IReactPackage>` returned by the `Packages` method


## Usage
```javascript
import RNTcpSsl from 'react-native-tcp-ssl';

// TODO: What to do with the module?
RNTcpSsl;
```
  