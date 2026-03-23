import 'package:baxa/page%20b-acceuil/company/signin_page.dart';
import 'package:baxa/services/locale_service.dart';
import 'package:flutter/material.dart';

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
                padding: const EdgeInsets.symmetric(vertical: 6),
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
                            const Icon(
                              Icons.check_rounded,
                              color: _green,
                              size: 18,
                            ),
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
  }

  Widget _buildPickerField({
    required String? value,
    required String hint,
    required IconData icon,
    required VoidCallback onTap,
    String? helper,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value != null ? _greenMid : Colors.grey.shade300,
            width: value != null ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: value != null ? _green : Colors.grey.shade500,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value ?? hint,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: value != null
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: value != null
                          ? Colors.black87
                          : Colors.grey.shade500,
                    ),
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: value != null ? _green : Colors.grey.shade400,
                  size: 22,
                ),
              ],
            ),
            if (helper != null) ...[
              const SizedBox(height: 4),
              Text(helper, style: const TextStyle(fontSize: 11, color: _green)),
            ],
          ],
        ),
      ),
    );
  }

  void _continuer() {
    if (_typeSelectionne == null ||
        (_paysSupporte && _villeSelectionnee == null) ||
        (!_paysSupporte && _villeLibreController.text.trim().isEmpty)) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez remplir tous les champs')),
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
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
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: _greenLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.business_outlined,
                      size: 60,
                      color: _green,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Bienvenue sur Baxa',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Parlez-nous de votre entreprise',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 36),
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.07),
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
                              labelText: 'Nom de l\'entreprise',
                              hintText: 'Ex: Restaurant Chez Marie',
                              prefixIcon: const Icon(Icons.store_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: _green,
                                  width: 1.5,
                                ),
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
                            onTap: () => _showPicker(
                              title: 'Type d\'entreprise',
                              items: _typescompanies,
                              selected: _typeSelectionne,
                              onSelected: (val) => setState(() {
                                _typeSelectionne = val;
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
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: _green,
                                    width: 1.5,
                                  ),
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
                              onTap: () => _showPicker(
                                title: 'Ville',
                                items: _villesList,
                                selected: _villeSelectionnee,
                                onSelected: (val) =>
                                    setState(() => _villeSelectionnee = val),
                              ),
                            )
                          else
                            TextFormField(
                              controller: _villeLibreController,
                              textCapitalization: TextCapitalization.words,
                              decoration: InputDecoration(
                                labelText: 'Ville',
                                hintText: 'Entrez votre ville',
                                prefixIcon: const Icon(
                                  Icons.location_city_outlined,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: _green,
                                    width: 1.5,
                                  ),
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
                              Icon(
                                Icons.info_outline,
                                size: 14,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Ces informations nous aident à adapter Baxa à vos besoins',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
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
                          Text(
                            'Suivant',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
          ),
        ),
      ),
    );
  }
}
