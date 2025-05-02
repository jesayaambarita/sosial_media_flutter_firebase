import 'package:flutter/material.dart';

import '../screens/create_story_screen.dart';
import '../screens/home_mobile_screen.dart';

// Add this to your main.dart or routes configuration
final Map<String, WidgetBuilder> routes = {
  '/': (context) => HomeMobileScreen(),
  '/story-creator': (context) => StoryCreatorScreen(),
  // Other routes in your app
};

// Make sure to include the StoryDetailScreen in your imports,
// but it doesn't need a named route since we're using MaterialPageRoute
// to pass the stories data when navigating to it.