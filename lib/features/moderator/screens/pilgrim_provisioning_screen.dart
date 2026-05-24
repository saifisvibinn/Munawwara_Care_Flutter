import 'package:flutter/material.dart';

import '../widgets/provisioning/provisioning_tab.dart';

class PilgrimProvisioningScreen extends StatelessWidget {
  const PilgrimProvisioningScreen({super.key, this.isTabActive = true});

  final bool isTabActive;

  @override
  Widget build(BuildContext context) {
    return ProvisioningTab(isTabActive: isTabActive);
  }
}
