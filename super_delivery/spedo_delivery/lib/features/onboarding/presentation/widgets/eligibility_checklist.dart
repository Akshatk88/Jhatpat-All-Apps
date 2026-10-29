import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'onboarding_ui.dart';

/// Joining checklist — optional self-check, nothing here blocks submission
/// or is sent to the server. The partner just ticks what they have.
class EligibilityChecklist extends StatefulWidget {
  const EligibilityChecklist({super.key});

  static const items = [
    'ड्राइवर का पूरा नाम',
    'मोबाइल नंबर',
    'आधार से पहचान सत्यापन',
    'ड्राइविंग लाइसेंस',
    'गाड़ी का इंश्योरेंस',
    'गाड़ी की RC',
    'Android 5G फोन',
    'पर्याप्त इंटरनेट डेटा',
    'दो हेलमेट',
    'बंद जूते',
    'बाइक अधिकतम 3 साल पुरानी',
    'उम्र 18 से 38 वर्ष',
    'बाइक ड्राइवर के नाम पर',
    'ड्राइवर के नाम का बैंक अकाउंट',
  ];

  @override
  State<EligibilityChecklist> createState() => EligibilityChecklistState();
}

class EligibilityChecklistState extends State<EligibilityChecklist> {
  // Kept for the session so ticks survive moving between steps.
  static final _checked = <int>{};

  @override
  Widget build(BuildContext context) {
    const items = EligibilityChecklist.items;
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.fromLTRB(14.w, 12.h, 8.w, 8.h),
      decoration: BoxDecoration(
        color: OnboardingColors.card(context),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: OnboardingColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ज़रूरी जानकारी (वैकल्पिक)',
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.w800,
              color: OnboardingColors.text(context),
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            'जो आपके पास है उस पर टिक करें  •  ${_checked.length}/${items.length}',
            style: TextStyle(
              fontSize: 12.sp,
              color: OnboardingColors.muted(context),
            ),
          ),
          SizedBox(height: 4.h),
          for (var i = 0; i < items.length; i++)
            InkWell(
              borderRadius: BorderRadius.circular(8.r),
              onTap: () => setState(() =>
                  _checked.contains(i) ? _checked.remove(i) : _checked.add(i)),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 2.h),
                child: Row(
                  children: [
                    Checkbox(
                      value: _checked.contains(i),
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) => setState(() =>
                          v == true ? _checked.add(i) : _checked.remove(i)),
                    ),
                    Expanded(
                      child: Text(
                        '${i + 1}. ${items[i]}',
                        style: TextStyle(
                          fontSize: 13.5.sp,
                          color: OnboardingColors.text(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
