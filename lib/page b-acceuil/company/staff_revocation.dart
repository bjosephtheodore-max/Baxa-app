/// Message expliquant à un membre du staff pourquoi son accès a pris fin.
///
/// Le motif vient du champ `revokedReason` de sa fiche
/// `companies/{companyId}/staff/{uid}`, posé à la désactivation :
/// - `company_leaving` : l'établissement quitte Baxa (Cloud Function) ;
/// - `removed` : l'admin l'a retiré de l'équipe (team_page) ;
/// - `left` : il a lui-même quitté l'équipe → aucun message.
///
/// Affiché à la déconnexion automatique (house_page) et à une tentative de
/// reconnexion (staff_auth_page).
class StaffRevocation {
  const StaffRevocation._(this.title, this.body);

  final String title;
  final String body;

  /// `null` quand il n'y a rien à expliquer (départ volontaire, motif absent).
  static StaffRevocation? of(String? reason, String companyName) {
    final name = companyName.trim();
    switch (reason) {
      case 'company_leaving':
        return StaffRevocation._(
          '${name.isEmpty ? "L'établissement" : name} quitte Baxa',
          "Votre accès à l'espace équipe a pris fin. Si l'établissement "
              'revient, votre responsable vous enverra un nouveau code '
              "d'invitation.",
        );
      case 'removed':
        final team = name.isEmpty ? "l'équipe" : "l'équipe de $name";
        return StaffRevocation._(
          "Accès à l'équipe terminé",
          'Vous avez été retiré de $team. Pour revenir, demandez un nouveau '
              "code d'invitation à votre responsable.",
        );
      default:
        return null;
    }
  }
}
