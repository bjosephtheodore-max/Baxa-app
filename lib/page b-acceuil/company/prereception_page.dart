import 'package:baxa/page%20b-acceuil/company/signin_page.dart';
import 'package:baxa/services/locale_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

class PrereceptionPage extends StatefulWidget {
  const PrereceptionPage({super.key});

  @override
  State<PrereceptionPage> createState() => _PrereceptionPageState();
}

class _PrereceptionPageState extends State<PrereceptionPage> {
  static const Color _green = Color(0xFF4B8B5E);
  static const Color _greenLight = Color(0xFFE8F5ED);
  static const Color _greenMid = Color(0xFFB2D3C2);
  static const Color _dark = Color(0xFF1E2D23);

  final _formKey = GlobalKey<FormState>();
  final _nomEntrepriseController = TextEditingController();
  final _autreTypeController = TextEditingController();
  final _villeLibreController = TextEditingController();

  String? _typeSelectionne;
  bool _afficherChampAutre = false;
  String? _villeSelectionnee;
  bool _typeError = false;
  bool _villeError = false;

  final List<String> _villesList = LocaleService.villes;
  final bool _paysSupporte = LocaleService.isPaysSupporte;
  final String _countryCode = LocaleService.countryCode ?? 'XX';

  final List<String> _typescompanies = [
    'Banque',
    'Restaurant',
    'Commerce',
    'Administration',
    'Autre',
  ];

  @override
  void dispose() {
    _nomEntrepriseController.dispose();
    _autreTypeController.dispose();
    _villeLibreController.dispose();
    super.dispose();
  }

  Future<void> _showPicker({
    required String title,
    required List<String> items,
    required String? selected,
    required void Function(String) onSelected,
  }) async {
    FocusScope.of(context).unfocus();
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _dark,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Divider(color: Colors.grey.shade100, height: 1),
            Flexible(
              child: ListView.builder(
                padding: EdgeInsets.only(
                  top: 6,
                  bottom: 6 + MediaQuery.of(ctx).padding.bottom,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final item = items[i];
                  final isSelected = item == selected;
                  return InkWell(
                    onTap: () {
                      onSelected(item);
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? _greenLight : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected ? _green : Colors.black87,
                              ),
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check_rounded,
                                color: _green, size: 18),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (mounted) FocusScope.of(context).requestFocus(FocusNode());
  }

  Widget _buildPickerField({
    required String? value,
    required String hint,
    required IconData icon,
    required VoidCallback onTap,
    String? helper,
    bool error = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: error
                ? Colors.red.shade300
                : value != null
                    ? _greenMid
                    : Colors.grey.shade300,
            width: error || value != null ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    size: 20,
                    color: value != null ? _green : Colors.grey.shade500),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value ?? hint,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          value != null ? FontWeight.w600 : FontWeight.w400,
                      color: value != null
                          ? Colors.black87
                          : Colors.grey.shade500,
                    ),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down_rounded,
                    color: value != null ? _green : Colors.grey.shade400,
                    size: 22),
              ],
            ),
            if (helper != null) ...[
              const SizedBox(height: 4),
              Text(helper,
                  style: const TextStyle(fontSize: 11, color: _green)),
            ],
          ],
        ),
      ),
      if (error) ...[
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(
            'Obligatoire',
            style: TextStyle(fontSize: 12, color: Colors.red.shade600),
          ),
        ),
      ],
        ],
      ),
    );
  }

  void _continuer() {
    setState(() {
      _typeError = _typeSelectionne == null;
      _villeError = _paysSupporte && _villeSelectionnee == null;
    });
    final formValid = _formKey.currentState!.validate();
    if (_typeError || _villeError || !formValid) return;
    if (formValid) {
      final typeFinal = _afficherChampAutre
          ? _autreTypeController.text.trim()
          : _typeSelectionne!;
      final villeFinale = _paysSupporte
          ? _villeSelectionnee!
          : _villeLibreController.text.trim();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SigninPage(
            nomEntreprise: _nomEntrepriseController.text.trim(),
            typeEntreprise: typeFinal,
            typeCategorie: _afficherChampAutre ? 'Autre' : typeFinal,
            ville: villeFinale,
            country: _countryCode,
            language: LocaleService.languageCode,
            locale: LocaleService.localeString,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
        ),
      ),
      body: Container(
        color: Colors.white,
        child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                const SizedBox(height: 0),

                // Animation d'accueil
                SizedBox(
                  height: 140,
                  child: Lottie.asset(
                    'assets/animations/Handshake Loop.json',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),

                const SizedBox(height: 20),

                // Titre
                const Text(
                  'Parlez-nous de votre Structure',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _dark,
                    height: 1.3,
                  ),
                ),

                const SizedBox(height: 28),

                // Formulaire
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _nomEntrepriseController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: 'Nom de la structure',
                            hintText: 'Ex: Banque Populaire, Mairie...',
                            prefixIcon: const Icon(Icons.store_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: _green, width: 1.5),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Le nom est obligatoire'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        _buildPickerField(
                          value: _typeSelectionne,
                          hint: 'Sélectionnez le type',
                          icon: Icons.category_outlined,
                          error: _typeError,
                          onTap: () => _showPicker(
                            title: 'Type de structure',
                            items: _typescompanies,
                            selected: _typeSelectionne,
                            onSelected: (val) => setState(() {
                              _typeSelectionne = val;
                              _typeError = false;
                              _afficherChampAutre = val == 'Autre';
                              if (!_afficherChampAutre) {
                                _autreTypeController.clear();
                              }
                            }),
                          ),
                        ),
                        if (_afficherChampAutre) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _autreTypeController,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: 'Précisez le type',
                              hintText: 'Ex: Hôtel, École, Salon...',
                              prefixIcon: const Icon(Icons.edit_outlined),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: _green, width: 1.5),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            validator: (v) =>
                                (_afficherChampAutre &&
                                        (v == null || v.trim().isEmpty))
                                    ? 'Veuillez préciser le type'
                                    : null,
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (_paysSupporte)
                          _buildPickerField(
                            value: _villeSelectionnee,
                            hint: 'Sélectionnez votre ville',
                            icon: Icons.location_city_outlined,
                            helper: '📍 ${LocaleService.countryName} détecté',
                            error: _villeError,
                            onTap: () => _showPicker(
                              title: 'Ville',
                              items: _villesList,
                              selected: _villeSelectionnee,
                              onSelected: (val) => setState(() {
                                _villeSelectionnee = val;
                                _villeError = false;
                              }),
                            ),
                          )
                        else
                          TextFormField(
                            controller: _villeLibreController,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: 'Ville',
                              hintText: 'Entrez votre ville',
                              prefixIcon:
                                  const Icon(Icons.location_city_outlined),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    BorderSide(color: Colors.grey.shade300),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: _green, width: 1.5),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Veuillez entrer votre ville'
                                : null,
                          ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 14, color: Colors.grey.shade400),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Ces informations nous aident à adapter Baxa à vos besoins',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade500),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // Bouton
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _continuer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Suivant',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward, size: 18),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),  // SingleChildScrollView
      ),
    ),
    );
  }
}
