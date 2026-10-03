import 'package:baxa/page%20b-acceuil/company/company_day_preview_page.dart';
import 'package:baxa/page%20b-acceuil/company/company_onboarding_page.dart';
import 'package:baxa/services/locale_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PrereceptionPage extends StatefulWidget {
  const PrereceptionPage({super.key});

  @override
  State<PrereceptionPage> createState() => _PrereceptionPageState();
}

class _PrereceptionPageState extends State<PrereceptionPage> {
  static const Color _green = Color(0xFF4B8B5E);
  static const Color _greenDark = Color(0xFF3F7A51);
  static const Color _greenLight = Color(0xFFE8F5ED);
  static const Color _border = Color(0xFFD5DED8);
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
  void initState() {
    super.initState();
    CompanyOnboarding.logStep('structure');
  }

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

  // Libellé posé au-dessus du champ (et non intégré à sa bordure).
  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _dark,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: 1.5),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 15, color: Colors.grey.shade500),
      prefixIcon: Icon(icon, color: _green, size: 20),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      filled: true,
      fillColor: Colors.white,
      enabledBorder: border(_border),
      focusedBorder: border(_green),
      errorBorder: border(Colors.red.shade300),
      focusedErrorBorder: border(Colors.red.shade400),
    );
  }

  Widget _buildPickerField({
    required String? value,
    required String hint,
    required IconData icon,
    required VoidCallback onTap,
    String? helper,
    bool error = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: error ? Colors.red.shade300 : _border,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: _green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      value ?? hint,
                      style: TextStyle(
                        fontSize: 15,
                        color: value != null ? _dark : Colors.grey.shade500,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.grey.shade600,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Row(
              children: [
                const Icon(Icons.place_outlined, size: 14, color: _green),
                const SizedBox(width: 6),
                Text(
                  helper,
                  style: const TextStyle(fontSize: 12, color: _green),
                ),
              ],
            ),
          ),
        if (error)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(
              'Obligatoire',
              style: TextStyle(fontSize: 12, color: Colors.red.shade600),
            ),
          ),
      ],
    );
  }

  void _continuer() {
    setState(() {
      _typeError = _typeSelectionne == null;
      _villeError = _paysSupporte && _villeSelectionnee == null;
    });
    final formValid = _formKey.currentState!.validate();
    if (_typeError || _villeError || !formValid) return;
    final typeFinal = _afficherChampAutre
        ? _autreTypeController.text.trim()
        : _typeSelectionne!;
    final villeFinale = _paysSupporte
        ? _villeSelectionnee!
        : _villeLibreController.text.trim();
    // Étape intermédiaire « Une journée chez [Nom] », qui transmet ensuite
    // exactement ces valeurs à SigninPage.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CompanyDayPreviewPage(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          tooltip: 'Retour',
          icon: const Icon(
            Icons.chevron_left_rounded,
            color: _greenDark,
            size: 30,
          ),
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Parlez-nous de votre structure',
                            style: TextStyle(
                              fontSize: 26,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                              color: _dark,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Nous adaptons Baxa à votre activité.',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 24),

                          _label('Nom de la structure'),
                          TextFormField(
                            controller: _nomEntrepriseController,
                            textCapitalization: TextCapitalization.words,
                            style: const TextStyle(fontSize: 15, color: _dark),
                            decoration: _inputDecoration(
                              hint: 'Ex : Banque Populaire, Mairie…',
                              icon: Icons.store_outlined,
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Le nom est obligatoire'
                                : null,
                          ),
                          const SizedBox(height: 18),

                          _label('Type de structure'),
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
                            const SizedBox(height: 18),
                            _label('Précisez le type'),
                            TextFormField(
                              controller: _autreTypeController,
                              textCapitalization: TextCapitalization.words,
                              style:
                                  const TextStyle(fontSize: 15, color: _dark),
                              decoration: _inputDecoration(
                                hint: 'Ex : Hôtel, École, Salon…',
                                icon: Icons.edit_outlined,
                              ),
                              validator: (v) =>
                                  (_afficherChampAutre &&
                                      (v == null || v.trim().isEmpty))
                                  ? 'Veuillez préciser le type'
                                  : null,
                            ),
                          ],
                          const SizedBox(height: 18),

                          _label('Ville'),
                          if (_paysSupporte)
                            _buildPickerField(
                              value: _villeSelectionnee,
                              hint: 'Sélectionnez votre ville',
                              icon: Icons.location_city_outlined,
                              helper: '${LocaleService.countryName} détecté',
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
                              style:
                                  const TextStyle(fontSize: 15, color: _dark),
                              decoration: _inputDecoration(
                                hint: 'Entrez votre ville',
                                icon: Icons.location_city_outlined,
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Veuillez entrer votre ville'
                                  : null,
                            ),
                          const SizedBox(height: 20),

                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: _greenLight,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 18,
                                  color: _greenDark,
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Ces informations nous aident à adapter '
                                    'Baxa à vos besoins.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.45,
                                      color: Color(0xFF2F4A37),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _continuer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _greenDark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Suivant',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 10),
                      Icon(Icons.arrow_forward_rounded, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
