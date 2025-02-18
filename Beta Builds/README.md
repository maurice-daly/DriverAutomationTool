![MSEndpointMgr Driver Auatomation Tool - BETA Channel](https://msendpointmgr.com/wp-content/uploads/DAT/DAT1.jpg)

# Driver Automation Tool 8 BETA

Welcome to the BETA channel for the Driver Automation Tool.

The binaries contained within this channel will updated with additional functions, and should be used for testing. Feedback should be provided in the GitHub PR's and please make note of the in-work items before posting comments, as the item you are looking for could be in development.

Initial BETA Release - 16/02/2024
The new Driver Automation Tool has a redesigned UI which is designed to be easier to use and allow for more expansion. The initial release is for Configuration Manager ONLY, Intune support will follow in the upcoming BETA release updates. 

Current functionality
- Current OEM Support: Acer, Dell
- Package Type Support: Drivers
- Supported Operating Systems: Windows 10, Windows 11
- Supported Architectures : x64, x86

In Progress Functionality
- Additional OEM Support - HP/Lenovo/Microsoft (Expected by 22/02/2025)
- Add Microsoft support 
- Previous version removal 
- Intune Support
- Deployment Rings
- New UI for driver additions to existing packages
- Custom driver package UI

New UI
Elemeents have been moved to an application style layout, with previously contained tab elements migrated;

Configuration Manager Environment:

<img src="https://github.com/user-attachments/assets/1ba85731-6a47-4b14-8942-16b3f5cd8365" height="450" />


Configuration Manager Distribtion Point Configuration:

![image](https://github.com/user-attachments/assets/c95bf097-ce65-4a70-9ead-eafcc518da80){height=450}


Configuration Manager Package Management:

![image](https://github.com/user-attachments/assets/110b948e-1a77-40e5-8f32-ee1aacf2561d){height=150}

Configuration Manager Package Settings:

![image](https://github.com/user-attachments/assets/709638f8-5e58-4d04-9908-62d1fcbeefe3){height=150}

Shared Configuration Settings:

![image](https://github.com/user-attachments/assets/36fce782-0bf7-41fa-bd16-fde9361130c8){height=150}

Registry Storage
The Driver Automation Tool now uses the registry to store all of your configuration settings, and critical information about the package build process;

![image](https://github.com/user-attachments/assets/b3977d45-1492-4636-bf1d-236a4160af8d){height=150}


Configuration can now be exported and imported from the UI, using registry exports;

![image](https://github.com/user-attachments/assets/4b7eddbd-002c-4597-a4b6-4d8ae01562e0){height=150}

Download Utility
To provide additional feedback and control downloads better, CURL is used by the new release. This is packaged within the MSI.

![image](https://github.com/user-attachments/assets/dd487337-d489-45fd-9b54-a039e29e8fbf){height=150}

Fully Responsive UI

The Driver Automation Tool now uses background jobs to undertake the majority of actions, and this results in a fully responsive UI, something that I had taken as feedback from previous builds. With this includes the addition to lauch the log file (in CMTrace format) and abort the build process;

![image](https://github.com/user-attachments/assets/6c31e337-159e-42fa-b689-ff2abb834079){height=150}












