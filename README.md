Aplicatie - Flutter phone app.

coordonation_system - flask implementation for the server , docker and yaml files for kubernetes with hpa, and benchmakrs to test it.

PDF - Documentation in romanian for the porject.

Video - demo showing how the app works, and info received by the vehicles shown at the end.

This project implements a system for real-time visual localization and coordinated control of multiple remote-controlled (RC) vehicles using ArUco markers. The system is composed of a mobile application and a detection server. The mobile app, developed in Flutter, captures images using the phone's camera and sends them periodically to the server for processing.

The server, implemented in Python using Flask and deployed in a Kubernetes cluster, analyzes the received images to detect visual markers and calculate the positions of the vehicles and route markers in metric coordinates. Vehicles request their current position and the position of others by querying the server through a simple API.

The server tracks each vehicle's progress along a predefined route and notifies them when the route has been completed. The system is designed to scale automatically depending on the number of vehicles and image frequency, using containerization and horizontal pod autoscaling to maintain responsiveness.

Overall, the solution offers a low-cost, scalable and precise alternative to hardware-based localization, relying only on visual input and centralized processing to coordinate the movement of multiple autonomous units.
