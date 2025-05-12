import 'package:flutter/material.dart';

class BottomNavbar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final VoidCallback onRideButtonPressed;
  final VoidCallback onAlertButtonPressed;

  BottomNavbar({
    required this.currentIndex,
    required this.onTap,
    required this.onRideButtonPressed,
    required this.onAlertButtonPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64, // Increased height to accommodate the content
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            spreadRadius: 0,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: _buildNavItem(
              context: context,
              icon: Icons.location_on, // Changed from map to location_on icon
              label: 'Locations', // Changed from Map to Locations
              index: 0,
              defaultColor: Colors.grey, // Set default color to grey
            ),
          ),
          Expanded(
            child: _buildNavItem(
              context: context,
              icon: Icons.emergency,
              label: 'Emergency',
              index: 1,
              color: Colors.red,
            ),
          ),
          Expanded(child: _buildAlertButton()),
          Expanded(child: _buildRideButton()),
          Expanded(
            child: _buildNavItem(
              context: context,
              icon: Icons.person,
              label: 'Profile',
              index: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required int index,
    Color? color,
    Color? defaultColor,
  }) {
    final isSelected = currentIndex == index;
    final navColor = color ?? (defaultColor ?? Colors.blue);

    return InkWell(
      onTap: () => onTap(index),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 300),
        padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color:
              isSelected && color != null
                  ? navColor.withOpacity(0.1)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? (color ?? navColor) : Colors.grey,
              size: 20,
            ),
            SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? (color ?? navColor) : Colors.grey,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRideButton() {
    return InkWell(
      onTap: onRideButtonPressed,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 300),
        padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_taxi, color: Colors.grey, size: 20),
            SizedBox(height: 2),
            Text(
              'Ride',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertButton() {
    return InkWell(
      onTap: onAlertButtonPressed,
      borderRadius: BorderRadius.circular(50), // Circular shape
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.3),
              spreadRadius: 2,
              blurRadius: 5,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_outlined, color: Colors.white, size: 20),
            SizedBox(height: 2),
            Text(
              'Alert',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
