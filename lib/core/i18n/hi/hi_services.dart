// Hindi UI strings — services area. English text is the key, exactly as written
// in the code (same spacing, punctuation and {placeholders}).
const Map<String, String> hiServices = {
  // Module descriptors (label / tagline shown in the top switcher)
  'Rides': 'राइड',
  'Book a ride': 'राइड बुक करें',
  'Parcel': 'पार्सल',
  'Send anything': 'कुछ भी भेजें',
  'Food': 'खाना',
  'Food delivery': 'फ़ूड डिलीवरी',
  'Rentals': 'रेंटल',
  'Rent a vehicle': 'गाड़ी किराए पर लें',
  'Services': 'सर्विसेज़',
  'Home repairs': 'घर की मरम्मत',

  // data/models/sp_booking.dart — booking status labels
  'Finding a professional': 'प्रोफ़ेशनल ढूंढ रहे हैं',
  'Waiting for confirmation': 'कन्फ़र्मेशन का इंतज़ार',
  'Payment pending': 'पेमेंट बाकी है',
  'Pending': 'बाकी',
  'Confirmed': 'कन्फ़र्म',
  'Professional assigned': 'प्रोफ़ेशनल तय हो गया',
  'On the way': 'रास्ते में',
  'Arrived': 'पहुंच गए',
  'Work in progress': 'काम चल रहा है',
  'Completed': 'पूरा हुआ',
  'No professionals available': 'कोई प्रोफ़ेशनल उपलब्ध नहीं',
  'Cancelled': 'कैंसल',
  'Rejected': 'अस्वीकार',
  'Updating': 'अपडेट हो रहा है',
  // payment status labels
  'Paid': 'पेमेंट हो गया',
  'Payment failed': 'पेमेंट फ़ेल हो गया',
  'Refunded': 'रिफ़ंड हो गया',
  'Paid at doorstep': 'घर पर पेमेंट हुआ',
  'Covered by your plan': 'आपके प्लान में शामिल',
  'Professional': 'प्रोफ़ेशनल',

  // application/booking_draft_controller.dart — payment methods + errors
  'Pay after service': 'सर्विस के बाद पेमेंट करें',
  'Services wallet': 'सर्विसेज़ वॉलेट',
  'Pay online now': 'अभी ऑनलाइन पेमेंट करें',
  'Use my plan': 'मेरा प्लान इस्तेमाल करें',
  'Could not create the booking. Please try again.':
      'बुकिंग नहीं हो पाई। कृपया दोबारा कोशिश करें।',

  // application/my_bookings_controller.dart — tabs
  'Active': 'चालू',

  // application/sp_payment_controller.dart
  'Paid from your services wallet.': 'आपके सर्विसेज़ वॉलेट से पेमेंट हो गया।',
  'Online payment is unavailable right now. Please choose another method.':
      'ऑनलाइन पेमेंट अभी उपलब्ध नहीं है। कृपया कोई दूसरा तरीका चुनें।',
  'Payment successful.': 'पेमेंट सफल रहा।',
  'Payment received. Confirmation may take a moment to appear.':
      'पेमेंट मिल गया। कन्फ़र्मेशन दिखने में थोड़ा समय लग सकता है।',
  'Payment cancelled.': 'पेमेंट कैंसल हो गया।',
  'Payment failed. Please try again.': 'पेमेंट फ़ेल हो गया। कृपया दोबारा कोशिश करें।',

  // presentation/booking_detail_screen.dart
  'Booking': 'बुकिंग',
  'This booking no longer exists.': 'यह बुकिंग अब मौजूद नहीं है।',
  'We could not load this booking.': 'हम यह बुकिंग लोड नहीं कर पाए।',
  'Share this code at the door': 'दरवाज़े पर यह कोड बताएं',
  'Only give it to the professional once they arrive.':
      'प्रोफ़ेशनल के पहुंचने के बाद ही उन्हें यह कोड दें।',
  'Payment code': 'पेमेंट कोड',
  'Share only after the work is finished and billed.':
      'काम पूरा होने और बिल बनने के बाद ही बताएं।',
  'Rate this service': 'इस सर्विस को रेटिंग दें',
  'Reason: {reason}': 'कारण: {reason}',
  'Service booking': 'सर्विस बुकिंग',
  'On the move — arriving shortly': 'रास्ते में हैं — जल्द पहुंच रहे हैं',
  'Scheduled': 'तय समय',
  'Address': 'पता',
  'Payment confirmed. Thank you!': 'पेमेंट कन्फ़र्म हो गया। धन्यवाद!',
  'Final bill': 'फ़ाइनल बिल',
  'Estimated bill': 'अनुमानित बिल',
  'Total': 'कुल',
  'Service': 'सर्विस',
  'Discount': 'छूट',
  'Taxes': 'टैक्स',
  'Visiting charge': 'विज़िटिंग चार्ज',
  'I have paid {amount}': 'मैंने {amount} दे दिए',
  'Your rating': 'आपकी रेटिंग',
  'Cancel this booking?': 'यह बुकिंग कैंसल करें?',
  'A cancellation fee may apply depending on how close the appointment is.':
      'अपॉइंटमेंट का समय कितना नज़दीक है, इसके हिसाब से कैंसलेशन फ़ीस लग सकती है।',
  'Keep booking': 'बुकिंग रखें',
  'Cancel booking': 'बुकिंग कैंसल करें',
  'Booking cancelled.': 'बुकिंग कैंसल हो गई।',

  // presentation/booking_review_screen.dart
  'Could not create the booking.': 'बुकिंग नहीं हो पाई।',
  '{message} You can still pay after the service.':
      '{message} आप सर्विस के बाद भी पेमेंट कर सकते हैं।',
  'Review': 'रिव्यू',
  'Your booking details are incomplete.': 'आपकी बुकिंग की जानकारी अधूरी है।',
  'Review & confirm': 'जांचें और कन्फ़र्म करें',
  'Quantity {count}': 'संख्या {count}',
  'Service address': 'सर्विस का पता',
  'Your note': 'आपका नोट',
  'Change': 'बदलें',
  'Bill summary': 'बिल की जानकारी',
  'Previous cancellation fee': 'पिछली कैंसलेशन फ़ीस',
  'The final bill may change if the professional finds extra work or parts are needed. You approve it before paying.':
      'अगर प्रोफ़ेशनल को ज़्यादा काम मिले या पार्ट्स लगें तो फ़ाइनल बिल बदल सकता है। पेमेंट से पहले आप इसे मंज़ूर करेंगे।',
  'How would you like to pay?': 'आप कैसे पेमेंट करना चाहेंगे?',
  'Balance {amount}': 'बैलेंस {amount}',
  'Balance {amount} — not enough': 'बैलेंस {amount} — काफ़ी नहीं है',
  'Cash or online once the work is done': 'काम पूरा होने पर कैश या ऑनलाइन',
  'Card or net banking': 'कार्ड या नेट बैंकिंग',
  'Active plan': 'चालू प्लान',
  'Confirm booking · {amount}': 'बुकिंग कन्फ़र्म करें · {amount}',

  // presentation/booking_schedule_screen.dart
  'Please pick a date and an arrival window.': 'कृपया तारीख और आने का समय चुनें।',
  'Please pick a service first.': 'कृपया पहले कोई सर्विस चुनें।',
  'When & where': 'कब और कहां',
  'House / flat, building': 'मकान / फ़्लैट, बिल्डिंग',
  'Area, street (optional)': 'इलाका, गली (वैकल्पिक)',
  'Landmark (optional)': 'लैंडमार्क (वैकल्पिक)',
  'City': 'शहर',
  'State': 'राज्य',
  'Pincode': 'पिनकोड',
  'Required': 'ज़रूरी है',
  'Enter a valid 6-digit pincode': 'सही 6 अंकों का पिनकोड डालें',
  'Preferred date': 'पसंदीदा तारीख',
  'Arrival window': 'आने का समय',
  'Anything we should know? (optional)': 'कुछ और बताना चाहेंगे? (वैकल्पिक)',
  'e.g. AC is on the second floor balcony': 'जैसे: AC दूसरी मंज़िल की बालकनी में है',
  'Review booking': 'बुकिंग जांचें',
  'Today': 'आज',

  // presentation/booking_searching_screen.dart
  'Stop searching?': 'खोजना बंद करें?',
  'We will cancel this booking. You can book again at any time.':
      'हम यह बुकिंग कैंसल कर देंगे। आप कभी भी दोबारा बुक कर सकते हैं।',
  'Keep waiting': 'इंतज़ार करें',
  'This booking was cancelled.': 'यह बुकिंग कैंसल हो गई थी।',
  'No professionals were available for this slot.':
      'इस समय के लिए कोई प्रोफ़ेशनल उपलब्ध नहीं था।',
  'Try another time': 'किसी और समय कोशिश करें',
  'Alerting professionals near you…': 'आपके पास के प्रोफ़ेशनल को सूचना दे रहे हैं…',
  'Checking a wider area…': 'थोड़े बड़े इलाके में देख रहे हैं…',
  'Still looking. Some slots take a little longer.':
      'अभी भी ढूंढ रहे हैं। कुछ समय के लिए थोड़ा ज़्यादा वक्त लगता है।',
  'No one available': 'कोई उपलब्ध नहीं',
  'You have not been charged.': 'आपसे कोई पैसा नहीं लिया गया है।',

  // presentation/category_screen.dart
  'Nothing available here yet.\nTry another category.':
      'यहां अभी कुछ उपलब्ध नहीं है।\nकोई दूसरी कैटेगरी देखें।',
  'You appear to be offline.': 'लगता है आप ऑफ़लाइन हैं।',
  'We could not load these services.': 'हम ये सर्विसेज़ लोड नहीं कर पाए।',
  'All': 'सभी',

  // presentation/my_bookings_screen.dart
  'My bookings': 'मेरी बुकिंग',
  'Nothing booked right now': 'अभी कोई बुकिंग नहीं है',
  'No completed services yet': 'अभी तक कोई सर्विस पूरी नहीं हुई',
  'Nothing cancelled': 'कुछ भी कैंसल नहीं हुआ',
  'Book a service and track it here.': 'कोई सर्विस बुक करें और उसे यहां ट्रैक करें।',
  'Your finished services will appear here.': 'आपकी पूरी हुई सर्विसेज़ यहां दिखेंगी।',
  'Cancelled bookings will appear here.': 'कैंसल की गई बुकिंग यहां दिखेंगी।',

  // presentation/rate_service_sheet.dart
  'Thanks for the feedback!': 'आपके फ़ीडबैक के लिए धन्यवाद!',
  'How was the service?': 'सर्विस कैसी रही?',
  'Tell us more (optional)': 'और बताएं (वैकल्पिक)',
  'Submit rating': 'रेटिंग भेजें',

  // presentation/services_home_screen.dart
  'What do you need?': 'आपको क्या चाहिए?',
  'Offers for you': 'आपके लिए ऑफ़र',
  'Most booked': 'सबसे ज़्यादा बुक की गई',
  'Worth a look': 'ज़रूर देखें',
  'Search for services or professionals...': 'सर्विस या प्रोफ़ेशनल खोजें...',
  'Near me': 'मेरे पास',
  'Your booking': 'आपकी बुकिंग',
  'Flat ₹100 OFF': 'फ़्लैट ₹100 की छूट',
  'On minimum order value\non any service, big or small!':
      'न्यूनतम ऑर्डर वैल्यू पर\nकोई भी सर्विस, छोटी हो या बड़ी!',
  'SPECIAL OFFER': 'खास ऑफ़र',
  'EXPLORE': 'देखें',
  '*T&C Apply': '*नियम व शर्तें लागू',
  'from {price}': '{price} से शुरू',

  // presentation/service_detail_screen.dart
  'This service is no longer available.': 'यह सर्विस अब उपलब्ध नहीं है।',
  'We could not load this service.': 'हम यह सर्विस लोड नहीं कर पाए।',
  'per {unit}': 'प्रति {unit}',
  'About this service': 'इस सर्विस के बारे में',
  'Quantity': 'संख्या',
  'Verified professionals': 'वेरिफ़ाइड प्रोफ़ेशनल',
  'Transparent pricing': 'साफ़ कीमत',
  'OTP-verified visit': 'OTP से वेरिफ़ाइड विज़िट',
  '+ visiting charge': '+ विज़िटिंग चार्ज',
  'Schedule service': 'सर्विस शेड्यूल करें',

  // presentation/widgets/services_bottom_nav.dart
  'Home': 'होम',
  'Bookings': 'बुकिंग',
  'Track': 'ट्रैक',
  'Profile': 'प्रोफ़ाइल',

  // presentation/widgets/sp_widgets.dart
  'View all': 'सभी देखें',
  'SALE': 'सेल',
  'Book': 'बुक करें',
  'Try again': 'दोबारा कोशिश करें',
};
