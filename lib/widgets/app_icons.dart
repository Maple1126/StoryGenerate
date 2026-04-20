import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppIcons {
  
  // 底部导航图标
  static Widget story({double size = 24, Color? color}) {
    return SvgPicture.string(
      '''<svg width="$size" height="$size" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M4 6H20M4 12H20M4 18H20" stroke="${color?.toHex() ?? '#4A4A4A'}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>''',
      width: size,
      height: size,
    );
  }
  
  static Widget image({double size = 24, Color? color}) {
    return SvgPicture.string(
      '''<svg width="$size" height="$size" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <rect x="3" y="3" width="18" height="18" rx="2" ry="2" stroke="${color?.toHex() ?? '#4A4A4A'}" stroke-width="2"/>
        <circle cx="8.5" cy="8.5" r="1.5" fill="${color?.toHex() ?? '#4A4A4A'}"/>
        <polyline points="21 15 16 10 5 21" stroke="${color?.toHex() ?? '#4A4A4A'}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>''',
      width: size,
      height: size,
    );
  }
  
  static Widget video({double size = 24, Color? color}) {
    return SvgPicture.string(
      '''<svg width="$size" height="$size" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <polygon points="5 3 19 12 5 21 5 3" stroke="${color?.toHex() ?? '#4A4A4A'}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
        <rect x="2" y="6" width="14" height="12" rx="2" ry="2" stroke="${color?.toHex() ?? '#4A4A4A'}" stroke-width="2"/>
      </svg>''',
      width: size,
      height: size,
    );
  }
  
  static Widget profile({double size = 24, Color? color}) {
    return SvgPicture.string(
      '''<svg width="$size" height="$size" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" stroke="${color?.toHex() ?? '#4A4A4A'}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
        <circle cx="12" cy="7" r="4" stroke="${color?.toHex() ?? '#4A4A4A'}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>''',
      width: size,
      height: size,
    );
  }
  
  // 功能图标
  static Widget generate({double size = 24, Color? color}) {
    return SvgPicture.string(
      '''<svg width="$size" height="$size" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M12 2L14.09 8.26L21 9L15.5 13.74L17.59 20L12 16.27L6.41 20L8.5 13.74L3 9L9.91 8.26L12 2Z" stroke="${color?.toHex() ?? '#4A4A4A'}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>''',
      width: size,
      height: size,
    );
  }
  
  static Widget download({double size = 24, Color? color}) {
    return SvgPicture.string(
      '''<svg width="$size" height="$size" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" stroke="${color?.toHex() ?? '#4A4A4A'}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
        <polyline points="7 10 12 15 17 10" stroke="${color?.toHex() ?? '#4A4A4A'}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
        <line x1="12" y1="15" x2="12" y2="3" stroke="${color?.toHex() ?? '#4A4A4A'}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>''',
      width: size,
      height: size,
    );
  }
  
  static Widget play({double size = 24, Color? color}) {
    return SvgPicture.string(
      '''<svg width="$size" height="$size" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <polygon points="5 3 19 12 5 21 5 3" fill="${color?.toHex() ?? '#4A4A4A'}"/>
      </svg>''',
      width: size,
      height: size,
    );
  }
  
  static Widget pause({double size = 24, Color? color}) {
    return SvgPicture.string(
      '''<svg width="$size" height="$size" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <rect x="6" y="4" width="4" height="16" fill="${color?.toHex() ?? '#4A4A4A'}"/>
        <rect x="14" y="4" width="4" height="16" fill="${color?.toHex() ?? '#4A4A4A'}"/>
      </svg>''',
      width: size,
      height: size,
    );
  }
}

extension ColorExtension on Color {
  String toHex() {
    return '#${(toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }
}