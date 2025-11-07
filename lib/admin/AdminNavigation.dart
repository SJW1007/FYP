import 'package:flutter/material.dart';
import '../all user/Settings.dart';
import 'AdminHomePage.dart';
import 'AdminMakeupArtistListPage.dart';
import 'AdminReportPage.dart';

class AdminMainNavigation extends StatefulWidget {
  const AdminMainNavigation({super.key});

  @override
  State<AdminMainNavigation> createState() => AdminMainNavigationState();
}

class AdminMainNavigationState extends State<AdminMainNavigation> {
  int _currentIndex = 0;
  String _listFilter = 'pending';

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  // Handle list page with filters
  Widget _buildListPage(String filter) {
    return AdminMakeupArtistList(initialFilter: filter);
  }

  // Build pages dynamically instead of using IndexedStack
  Widget _buildCurrentPage({String? listFilter}) {
    switch (_currentIndex) {
      case 0:
        return const AdminHomePage();
      case 1:
        return _buildListPage(listFilter ?? 'pending');
      case 2:
        return const AdminReportsPage();
      case 3:
        return const SettingsPage();
      default:
        return const AdminHomePage();
    }
  }

  // Handle navigation with filters
  void navigateToList(String filter) {
    setState(() {
      _currentIndex = 1;
      _listFilter = filter;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildCurrentPage(listFilter: _listFilter),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFFDA9BF5),
        unselectedItemColor: Colors.grey,
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'List',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_books_rounded),
            label: 'Report',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}