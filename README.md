# FinTrack

FinTrack is a modern iOS application designed to help users track their financial investments and stay updated with market news. Built with SwiftUI, it provides a seamless and intuitive user experience for managing your investment portfolio.

## Features

- **Portfolio Management**: Track your crypto and stock investments in one place
- **Real-time Market Data**: Get up-to-date prices and market information
- **Portfolio Analytics**: View your portfolio distribution and performance through interactive charts
- **Market News**: Stay informed with the latest financial news
- **Asset Search**: Easily find and add new assets to your portfolio
- **User Profiles**: Personalize your experience with user accounts
- **Real-time Updates**: Get live updates on your portfolio value
- **User Authentication**: Secure Google Sign-In integration

## Technical Stack

- **Framework**: SwiftUI
- **Architecture**: MVVM (Model-View-ViewModel)
- **Dependencies**: 
  - Firebase Authentication
  - Charts Framework
  - Combine Framework
  - RESTful APIs

## Requirements

- iOS 15.0+
- Xcode 13.0+
- Swift 5.5+

## Installation

1. Clone the repository
```bash
git clone https://github.com/CankatCaglar/FinTrack.git
```

2. Open the project in Xcode
```bash
cd FinTrack
open Fintrack.xcodeproj
```

3. Install dependencies using Swift Package Manager (SPM)
4. Build and run the project

## Configuration

To run the project, you'll need to:

1. Set up a Firebase project and add your `GoogleService-Info.plist`
2. Configure your API keys in `APIConstants.swift`

## Architecture

The project follows the MVVM (Model-View-ViewModel) architecture pattern:

- **Models**: Data models and business logic
- **Views**: SwiftUI views and UI components
- **ViewModels**: Business logic and data management
- **Services**: Network and data services

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contact

Cankat Caglar - [GitHub](https://github.com/CankatCaglar)
