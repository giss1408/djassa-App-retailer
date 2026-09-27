/// User-facing text, French first.
///
/// French is the working language of Côte d'Ivoire, the first market, and the
/// backend's country config lists `fr` and `dioula` for CI
/// (`app/core/countries.py:22`). The strings live in one class so the move to
/// real per-locale files is a mechanical change rather than a hunt through
/// widgets.
///
/// Not using `flutter_localizations` + ARB yet: it pulls in a large dependency
/// and generated code for a single locale. That is the wrong trade until a
/// second locale actually ships.
///
/// Rules for anything added here:
///
/// * **Plain words a merchant uses.** No "synchronisation", no "idempotent",
///   no "transaction" where "vente" works.
/// * **Never blame the merchant** for a failure the network caused.
/// * **Short.** A cheap phone at 320dp wide has little room, and these strings
///   must not be truncated mid-word.
class Strings {
  const Strings._();

  // Sign-in
  static const signInSubtitle = 'Espace marchand';
  static const username = 'Identifiant';
  static const password = 'Mot de passe';
  static const signIn = 'Se connecter';
  static const signingIn = 'Connexion...';
  static const signInRejected = 'Identifiant ou mot de passe incorrect.';
  static const signOut = 'Se deconnecter';

  // Home
  static const today = "Aujourd'hui";
  static const salesToday = 'ventes du jour';
  static const noSalesYet = 'Aucune vente enregistree aujourd\'hui.';
  static const recordSale = 'Enregistrer une vente';
  static const recentSales = 'Dernieres ventes';

  // Sync status. The merchant needs to know what has left the phone and what
  // has not, in words, not a spinner.
  static const allSent = 'Tout est envoye';
  static const waitingToSend = 'en attente d\'envoi';
  static const sendNow = 'Envoyer maintenant';
  static const sending = 'Envoi...';
  static const sentOk = 'Ventes envoyees';
  static const noConnection = 'Pas de connexion. Les ventes restent sur le telephone.';
  static const needsAttention = 'a verifier';

  // Record a sale
  static const amount = 'Montant';
  static const amountHint = 'Ex : 1500';
  static const saleType = 'Type';
  static const customerOptional = 'Client (optionnel)';
  static const customerHint = 'Numero de telephone';
  static const save = 'Enregistrer';
  static const saving = 'Enregistrement...';
  static const savedOffline = 'Vente enregistree sur le telephone.';
  static const savedAndSending = 'Vente enregistree.';
  static const amountRequired = 'Entrez un montant.';
  static const amountInvalid = 'Montant invalide.';

  // Sale states, in the merchant's terms rather than ours.
  static const statePending = 'Pas encore envoyee';
  static const stateSynced = 'Envoyee';
  static const stateRejected = 'Refusee';
  static const retry = 'Reessayer';

  // What "djassa" means. Accents dropped, as everywhere in this file.
  static const aboutNameLink = 'Que veut dire djassa ?';
  static const aboutNameTitle = 'Le mot djassa';
  static const aboutNameGrammar = '/dja.sa/ - nom';
  static const aboutNameOrigin = 'Nouchi, la langue de la rue a Abidjan';
  static const aboutNameSense1 =
      'Marche informel de rue : le marche spontane, au bord de la route ou '
      'dans le quartier, ou l\'on vend de tout, des habits de seconde main aux '
      'telephones, souvent sans etal officiel ni autorisation.';
  static const aboutNameSense2 =
      'Par extension, la rue, le quartier : le monde de l\'economie '
      'informelle et de la debrouille de tous les jours. Un milieu dur et '
      'vivant, ou l\'on s\'en sort grace aux petits commerces, aux affaires et '
      'au sens de la rue.';
  static const aboutNameWhy =
      'Djassa est fait pour les commercants du djassa : votre activite est '
      'bien reelle, l\'application en garde la preuve.';

  /// Sale categories. Kept short because the backend caps `type` at 32 chars
  /// and a merchant should not be typing a category at the counter.
  static const saleTypes = <String, String>{
    'sale': 'Vente',
    'service': 'Service',
    'credit': 'Credit',
  };
}
