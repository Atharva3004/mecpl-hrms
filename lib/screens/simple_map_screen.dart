// import 'package:flutter/material.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:geolocator/geolocator.dart';

// class SimpleMapScreen extends StatefulWidget {
//   const SimpleMapScreen({super.key});

//   @override
//   State<SimpleMapScreen> createState() => _SimpleMapScreenState();
// }

// class _SimpleMapScreenState extends State<SimpleMapScreen> {
//   LatLng? currentLocation;

//   @override
//   void initState() {
//     super.initState();
//     getLocation();
//   }

//   Future<void> getLocation() async {
//     // Request permission
//     LocationPermission permission = await Geolocator.requestPermission();

//     // Get current position
//     Position position = await Geolocator.getCurrentPosition();

//     setState(() {
//       currentLocation = LatLng(position.latitude, position.longitude);
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text("Simple Map")),

//       body: currentLocation == null
//           ? const Center(child: CircularProgressIndicator())
//           : GoogleMap(
//               initialCameraPosition: CameraPosition(
//                 target: currentLocation!,
//                 zoom: 15,
//               ),

//               myLocationEnabled: true, // blue dot

//               markers: {
//                 Marker(
//                   markerId: const MarkerId("current"),
//                   position: currentLocation!,
//                 ),
//               },
//             ),
//     );
//   }
// }
