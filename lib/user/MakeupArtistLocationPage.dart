import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:permission_handler/permission_handler.dart';

class MakeupArtistLocationPage extends StatefulWidget {
  final String artistName;
  final String address;
  final String profilePicture;

  const MakeupArtistLocationPage({
    super.key,
    required this.artistName,
    required this.address,
    required this.profilePicture,
  });

  @override
  State<MakeupArtistLocationPage> createState() => _MakeupArtistLocationPageState();
}

class _MakeupArtistLocationPageState extends State<MakeupArtistLocationPage> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  double? _latitude;
  double? _longitude;
  bool _isLoading = true;
  String? _errorMessage;
  bool _locationPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
    _geocodeAddress();
  }

  // Request location permission
  Future<void> _requestLocationPermission() async {
    try {
      final status = await Permission.location.request();
      setState(() {
        _locationPermissionGranted = status == PermissionStatus.granted;
      });

      if (status == PermissionStatus.denied) {
        print('📍 Location permission denied');
      } else if (status == PermissionStatus.permanentlyDenied) {
        print('📍 Location permission permanently denied');
        _showPermissionDialog();
      }
    } catch (e) {
      print('❌ Error requesting location permission: $e');
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Location Permission Required'),
          content: const Text(
            'This app needs location permission to show your current location on the map. Please enable it in Settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  // Google Geocoding API - converts address to coordinates
  Future<void> _geocodeAddress() async {
    final googleMapsApiKey = dotenv.env['GOOGLE_MAP'];

    print('🔑 API Key loaded: ${googleMapsApiKey != null ? 'Yes' : 'No'}');
    print('📍 Address to geocode: ${widget.address}');

    if (googleMapsApiKey == null || googleMapsApiKey.isEmpty) {
      setState(() {
        _errorMessage = 'Google Maps API key not configured';
        _isLoading = false;
      });
      return;
    }

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final encodedAddress = Uri.encodeComponent(widget.address);
      final url = 'https://maps.googleapis.com/maps/api/geocode/json?address=$encodedAddress&key=$googleMapsApiKey';

      print('🌐 Making geocoding request to: $url');

      final response = await http.get(Uri.parse(url));
      print('📡 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final location = data['results'][0]['geometry']['location'];
          _latitude = location['lat'].toDouble();
          _longitude = location['lng'].toDouble();
          print('📌 Coordinates found: $_latitude, $_longitude');
          _setMarker();
        } else {
          print('❌ Geocoding failed: ${data['status']}');
          String errorMsg = 'Could not find location';
          // Handle specific error cases
          switch (data['status']) {
            case 'ZERO_RESULTS':
              errorMsg = 'Address not found. Please check the address.';
              break;
            case 'OVER_QUERY_LIMIT':
              errorMsg = 'Too many requests. Please try again later.';
              break;
            case 'REQUEST_DENIED':
              errorMsg = 'Request denied. Check API key configuration.';
              break;
            case 'INVALID_REQUEST':
              errorMsg = 'Invalid request. Address may be malformed.';
              break;
            default:
              errorMsg = 'Geocoding error: ${data['status']}';
          }
          setState(() {
            _errorMessage = errorMsg;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Network error: ${response.statusCode}';
        });
      }
    } catch (e) {
      print('💥 Exception during geocoding: $e');
      setState(() {
        _errorMessage = 'Error finding location: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _setMarker() {
    if (_latitude != null && _longitude != null) {
      print('📍 Setting marker at: $_latitude, $_longitude');
      setState(() {
        _markers = {
          Marker(
            markerId: MarkerId(widget.artistName),
            position: LatLng(_latitude!, _longitude!),
            infoWindow: InfoWindow(
              title: widget.artistName,
              snippet: widget.address,
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          ),
        };
      });
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    print('🗺️ Google Map created successfully');
    _mapController = controller;
    // Move camera to the location if coordinates are available
    if (_latitude != null && _longitude != null) {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(_latitude!, _longitude!),
            zoom: 15.0,
          ),
        ),
      );
    }
  }

  Future<void> _openInMaps() async {
    // Try to use coordinates first (more accurate), fall back to address
    String url;
    if (_latitude != null && _longitude != null) {
      url = 'https://www.google.com/maps/search/?api=1&query=$_latitude,$_longitude';
    } else {
      final encodedAddress = Uri.encodeComponent(widget.address);
      url = 'https://www.google.com/maps/search/?api=1&query=$encodedAddress';
    }

    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      _showErrorSnackBar('Could not open Google Maps');
    }
  }

  Future<void> _getDirections() async {
    // Try to use coordinates first (more accurate), fall back to address
    String url;
    if (_latitude != null && _longitude != null) {
      url = 'https://www.google.com/maps/dir/?api=1&destination=$_latitude,$_longitude';
    } else {
      final encodedAddress = Uri.encodeComponent(widget.address);
      url = 'https://www.google.com/maps/dir/?api=1&destination=$encodedAddress';
    }

    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      _showErrorSnackBar('Could not open Google Maps for directions');
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red[400],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildMapView() {
    if (_isLoading) {
      return Container(
        color: Colors.grey[200],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: Color(0xFFDA9BF5),
              ),
              SizedBox(height: 16),
              Text(
                'Finding location...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null || _latitude == null || _longitude == null) {
      return Container(
        color: Colors.grey[200],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.location_off,
                size: 80,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  _errorMessage ?? 'Location not available',
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Unable to locate this address on the map',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _geocodeAddress,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDA9BF5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GoogleMap(
      onMapCreated: _onMapCreated,
      initialCameraPosition: CameraPosition(
        target: LatLng(_latitude!, _longitude!),
        zoom: 15.0,
      ),
      markers: _markers,
      myLocationEnabled: _locationPermissionGranted,
      myLocationButtonEnabled: _locationPermissionGranted,
      compassEnabled: true,
      mapToolbarEnabled: false,
      mapType: MapType.normal,
      trafficEnabled: false,
      buildingsEnabled: true,
      zoomGesturesEnabled: true,
      scrollGesturesEnabled: true,
      tiltGesturesEnabled: true,
      rotateGesturesEnabled: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Location',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Background Image
            Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/image_4.png'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            // Main Content
            Column(
              children: [
                // Artist Info Card
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      ClipOval(
                        child: Image.network(
                          widget.profilePicture,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 80,
                              height: 80,
                              decoration: const BoxDecoration(
                                color: Colors.grey,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.person, size: 40, color: Colors.white),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.artistName,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.location_on, size: 20, color: Color(0xFFDA9BF5)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    widget.address,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                      height: 1.3,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Map View
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildMapView(),
                  ),
                ),

                // Action Buttons
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _getDirections,
                          icon: const Icon(Icons.directions, size: 20),
                          label: const Text('Get Directions'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDA9BF5),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                            elevation: 3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _openInMaps,
                          icon: const Icon(Icons.map, size: 20),
                          label: const Text('Open in Maps'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFFDA9BF5),
                            side: const BorderSide(color: Color(0xFFDA9BF5), width: 2),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                            elevation: 3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}