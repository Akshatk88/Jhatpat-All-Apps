// Hindi UI strings — common area. English text is the key, exactly as written
// in the code (same spacing, punctuation and {placeholders}).
const Map<String, String> hiCommon = {
  // ── app/super_app.dart
  'Notifications Disabled': 'नोटिफिकेशन बंद हैं',
  'Notifications are required to receive real-time updates about your food orders (Order Accepted, Out for Delivery, Delivered, etc.). Please enable notifications in App Settings.':
      'अपने फ़ूड ऑर्डर की लाइव अपडेट (ऑर्डर स्वीकार हुआ, डिलीवरी के लिए निकला, डिलीवर हो गया आदि) पाने के लिए नोटिफिकेशन ज़रूरी हैं। कृपया ऐप सेटिंग्स में नोटिफिकेशन चालू करें।',
  'Later': 'बाद में',
  'Open Settings': 'सेटिंग्स खोलें',

  // ── app/shell/widgets/super_app_header.dart
  'Current Location': 'मौजूदा लोकेशन',
  'Fetching address…': 'पता ढूँढ रहे हैं…',
  'Deliver to • {label}': 'यहाँ डिलीवर करें • {label}',

  // ── module switcher (module labels + taglines)
  'Food': 'खाना',
  'Rides': 'राइड',
  'Rentals': 'किराये पर',
  'Food delivery': 'खाना डिलीवरी',
  'Send anything': 'कुछ भी भेजें',
  'Rent a vehicle': 'गाड़ी किराये पर लें',
  'Home repairs': 'घर की मरम्मत',
  'Book a ride': 'राइड बुक करें',

  // ── bottom navigation bars
  'Ride': 'राइड',
  'Services': 'सर्विसेज़',
  'Parcel': 'पार्सल',
  'History': 'हिस्ट्री',
  'Profile': 'प्रोफ़ाइल',
  'Home': 'होम',
  'Orders': 'ऑर्डर',

  // ── app/hub/hub_screen.dart
  'What do you need?': 'आपको क्या चाहिए?',
  'Food, rides and more — one app.': 'खाना, राइड और भी बहुत कुछ — एक ही ऐप में।',
  'Wallet': 'वॉलेट',
  'Notifications': 'नोटिफिकेशन',
  'Refer & earn': 'रेफ़र करें और कमाएँ',
  'Help': 'मदद',

  // ── app/routing/app_router.dart
  'Web View': 'वेब पेज',
  'Page not found': 'पेज नहीं मिला',
  'Go to home': 'होम पर जाएँ',

  // ── design_system/components/layout/webview_screen.dart
  'Invalid web page URL': 'वेब पेज का URL सही नहीं है',
  'Could not launch external browser.': 'ब्राउज़र नहीं खुल सका।',
  'Reload': 'फिर से लोड करें',
  'Open in Browser': 'ब्राउज़र में खोलें',
  'Failed to load page': 'पेज लोड नहीं हो सका',
  'Please check your internet connection and try again.':
      'कृपया अपना इंटरनेट कनेक्शन जाँचें और फिर से कोशिश करें।',
  'Try Again': 'फिर से कोशिश करें',

  // ── design_system/components/buttons/announce_button.dart
  'Stop': 'रोकें',
  'Suniye': 'सुनिए',

  // ── design_system/components/feedback/offline_banner.dart
  'No internet connection': 'इंटरनेट कनेक्शन नहीं है',

  // ── design_system/components/feedback/exit_confirmation_dialog.dart
  'Exit Jhatpat?': 'ऐप से बाहर निकलें?',
  'Are you sure you want to exit the app?': 'क्या आप सच में ऐप से बाहर निकलना चाहते हैं?',
  'Cancel': 'रद्द करें',
  'Exit': 'बाहर निकलें',

  // ── design_system/components/ride/ride_card.dart (status chip)
  'Completed': 'पूरी हुई',
  'Cancelled': 'रद्द',
  'Scheduled': 'शेड्यूल्ड',

  // ── core/error/failures.dart + core/network/api_client.dart
  'Something went wrong. Please try again.': 'कुछ गड़बड़ हो गई। कृपया फिर से कोशिश करें।',
  'No internet connection.': 'इंटरनेट कनेक्शन नहीं है।',
  'The request timed out. Please try again.': 'रिक्वेस्ट का समय खत्म हो गया। कृपया फिर से कोशिश करें।',
  'Session expired. Please log in again.': 'सेशन खत्म हो गया। कृपया फिर से लॉग इन करें।',
  'Please check the details and try again.': 'कृपया जानकारी जाँचें और फिर से कोशिश करें।',
  'Too many attempts. Please wait a moment and try again.':
      'बहुत ज़्यादा कोशिशें हो गईं। थोड़ा रुककर फिर से कोशिश करें।',
  'Too many attempts. Please wait and try again.':
      'बहुत ज़्यादा कोशिशें हो गईं। थोड़ा रुककर फिर से कोशिश करें।',
  'Not found.': 'नहीं मिला।',
  'Secure connection failed.': 'सुरक्षित कनेक्शन नहीं बन सका।',
  'Request cancelled.': 'रिक्वेस्ट रद्द हो गई।',

  // ── core/error/taxi_api_exception.dart
  'The connection timed out. Please try again.': 'कनेक्शन का समय खत्म हो गया। कृपया फिर से कोशिश करें।',
  'Unable to reach the server. Check your internet connection.':
      'सर्वर से कनेक्ट नहीं हो पा रहा। अपना इंटरनेट कनेक्शन जाँचें।',
  'Request was cancelled.': 'रिक्वेस्ट रद्द कर दी गई।',

  // ── core/location/location_service.dart
  'Location services (GPS) are turned off. Please turn on location services and try again.':
      'लोकेशन (GPS) बंद है। कृपया लोकेशन चालू करें और फिर से कोशिश करें।',
  'Location permission was denied.': 'लोकेशन की अनुमति नहीं दी गई।',
  'Location permission is permanently denied. Please enable it in app settings.':
      'लोकेशन की अनुमति हमेशा के लिए बंद है। कृपया ऐप सेटिंग्स में इसे चालू करें।',
  'Could not obtain current location. Please make sure GPS is active.':
      'मौजूदा लोकेशन नहीं मिल सकी। कृपया देखें कि GPS चालू है।',

  // ── core/payment/payment_gateway.dart
  'Online payment is not available right now. Your order was not charged.':
      'ऑनलाइन पेमेंट अभी उपलब्ध नहीं है। आपके ऑर्डर का कोई पैसा नहीं कटा।',
  'Wallet top-up is unavailable right now.': 'वॉलेट टॉप-अप अभी उपलब्ध नहीं है।',
  'Could not open the payment screen.': 'पेमेंट स्क्रीन नहीं खुल सकी।',
  'Wallet topped up successfully.': 'वॉलेट में पैसे सफलतापूर्वक जुड़ गए।',
  'Missing order reference.': 'ऑर्डर की जानकारी नहीं मिली।',
  'Payment successful.': 'पेमेंट सफल रहा।',
  'We are confirming your payment. This can take a moment.':
      'हम आपका पेमेंट कन्फ़र्म कर रहे हैं। इसमें थोड़ा समय लग सकता है।',
  'Payment cancelled.': 'पेमेंट रद्द हो गया।',
  'Payment failed.': 'पेमेंट नहीं हो सका।',
  'Completing payment in your wallet app.': 'आपके वॉलेट ऐप में पेमेंट पूरा हो रहा है।',

  // ── core/push/push_service.dart
  'Order Update': 'ऑर्डर अपडेट',

  // ── core/speech/speech_service.dart
  'Microphone permission denied. Please enable it in device Settings.':
      'माइक्रोफ़ोन की अनुमति नहीं मिली। कृपया फ़ोन की सेटिंग्स में इसे चालू करें।',
  'Voice recognition unavailable on this device/browser.':
      'इस डिवाइस/ब्राउज़र पर आवाज़ पहचानने की सुविधा उपलब्ध नहीं है।',
  'Unable to start speech recognition: {error}': 'आवाज़ पहचानना शुरू नहीं हो सका: {error}',

  // ── core/utils/taxi_validators.dart
  'Enter a valid 10-digit phone number': 'सही 10 अंकों का फ़ोन नंबर डालें',
  'Enter the {length}-digit OTP': '{length} अंकों का OTP डालें',
  'This field': 'यह फ़ील्ड',
  '{field} is required': '{field} ज़रूरी है',
  'Enter a valid email address': 'सही ईमेल पता डालें',

  // ── core/utils/taxi_formatters.dart
  '{minutes} min': '{minutes} मिनट',
  '{hours} h': '{hours} घंटा',
  '{hours} h {minutes} min': '{hours} घंटा {minutes} मिनट',
};
