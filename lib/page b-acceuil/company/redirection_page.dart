import 'package:baxa/page b-acceuil/company/signin_page.dart';
import 'package:flutter/material.dart';
import 'package:baxa/page b-acceuil/company/company_page.dart';
import 'package:baxa/services/firebase/auth.dart';

class RedirectionPage extends StatefulWidget {
  const RedirectionPage({super.key});

  @override
  State<StatefulWidget> createState() {
    return _RedirectionPageState();
  }
}

class _RedirectionPageState extends State<RedirectionPage> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Auth().authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator();
        } else if (snapshot.hasData) {
          return const CompanyPage();
        } else {
          return const SigninPage();
        }
      },
    );
  }
}
