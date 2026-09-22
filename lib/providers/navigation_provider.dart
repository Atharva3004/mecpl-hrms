// Navigation Provider for Bottom Nav State
import 'package:flutter/foundation.dart';

class NavigationProvider extends ChangeNotifier {
  int _currentIndex = 0;
  bool _isInitialized = false;

  int get currentIndex => _currentIndex;
  bool get isInitialized => _isInitialized;

  NavigationProvider() {
    _initialize();
  }

  void _initialize() {
    _currentIndex = 0;
    _isInitialized = true;
  }

  void setIndex(int index) {
    if (_currentIndex != index) {
      _currentIndex = index;
      notifyListeners();
    }
  }

  void resetIndex() {
    _currentIndex = 0;
    notifyListeners();
  }
}
