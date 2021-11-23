# Video Human Detection

This is a demo project refereced from [coreml-survival-guide/MobileNetV2+SSDLite](https://github.com/hollance/coreml-survival-guide) 

User can choose a mp4 video file from `PhotoLibrary` and export result to `PhotoLibrary`

![1 - demo](images/1-demo.gif)

| ![2 - preview](images/2-preview.png) | ![3 - exported](images/3-exported.png) |
| ------------------------------------ | -------------------------------------- |



## Features

- run `Preview` to check human detection on screen.

- `Export` dectection result to `PhotoLibrary`



## TODOs

- Once one or more persons are detected, the app should start record video and save it into another 10 seconds duration video file (.mp4)
- Stop video recording automatically if no more person detected after the time of last detected video frame over than 5 seconds



## Limitations

- Currently only support `32BGRA` mp4 input
- Sometimes `PhotoLibrary` cannot load the video file into temprary folder, please try to select a shorter video, e.g. less than 1min.



## Installation

This will be compatible with the lastest public release of Swift.

### Requirements

- iOS 14+
- Xcode 13.0+

### Dependencies

- RxSwift
- ProgressHUD
- SnapKit
- SwifterSwift
- Then



## Licence

Parchment is released under the MIT license. See [LICENSE](https://github.com/erichsu/Parchment/blob/master/LICENSE.md) for details.

### 

