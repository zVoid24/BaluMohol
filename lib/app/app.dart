import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:balumohol/features/geofence/presentation/pages/geofence_map_page.dart';
import 'package:balumohol/features/geofence/providers/geofence_map_controller.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => GeofenceMapController(),
        ),
      ],
      child: MaterialApp(
        title: 'জিওফেন্স মানচিত্র',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const GeofenceMapPage(),
      ),
    );
  }
}
