import 'package:baxa/page b-acceuil/customer/signine_page.dart';
import 'package:flutter/material.dart';
import 'package:baxa/page b-acceuil/customer/customer_page.dart';
import 'package:baxa/services/firebase/auth.dart';

class RedirectionePage extends StatefulWidget {
  const RedirectionePage({super.key});

  @override
  State<StatefulWidget> createState() {
    return _RedirectionePageState();
  }
}

class _RedirectionePageState extends State<RedirectionePage> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Auth().authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator();
        } else if (snapshot.hasData) {
          return const CustomerPage();
        } else {
          return const SigninePage();
        }
      },
    );
  }
}
