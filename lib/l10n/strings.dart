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

  // Deals ("bons plans") shown to customers in the Djassa app.
  static const myDeals = 'Mes bons plans';
  static const myDealsIntro =
      'Vos offres apparaissent dans l\'application client Djassa, '
      'dans Bons plans et sur la page de votre commerce.';
  static const newDeal = 'Nouveau bon plan';
  static const noDeals = 'Aucun bon plan en cours.';
  static const noDealsHint =
      'Une offre attire de nouveaux clients : un plat moins cher, '
      'une reduction le mardi, un cadeau a partir de 5000 F.';
  static const dealsNeedConnection = 'Connexion necessaire pour voir et publier vos bons plans.';
  static const endDeal = 'Terminer';
  static const endDealConfirm = 'Terminer ce bon plan ?';
  static const endDealConfirmHint = 'Les clients ne le verront plus.';
  static const cancel = 'Annuler';
  static const dealEnded = 'Bon plan termine.';
  static const dealPublished = 'Bon plan publie.';
  static const sponsored = 'Mis en avant par Djassa';
  static const endsOn = 'Jusqu\'au';
  static const maxDealsHint = 'Maximum 5 bons plans en meme temps.';

  // New deal
  static const dealTitle = 'Titre de l\'offre';
  static const dealTitleHint = 'Ex : Poulet braise + attieke';
  static const dealKind = 'Type d\'offre';
  static const kindPercent = 'Reduction en %';
  static const kindPrice = 'Prix promo';
  static const percent = 'Reduction (%)';
  static const percentHint = 'Ex : 20';
  static const promoPrice = 'Prix promo (F)';
  static const originalPrice = 'Prix normal (F, optionnel)';
  static const dealDuration = 'Duree';
  static const dealDescription = 'Details (optionnel)';
  static const dealDescriptionHint = 'Ex : le midi en semaine, dans la limite des stocks';
  static const preview = 'Apercu pour vos clients';
  static const publish = 'Publier';
  static const publishing = 'Publication...';
  static const titleTooShort = 'Donnez un titre a votre offre.';
  static const nothingOffered = 'Indiquez une reduction ou un prix promo.';
  static const percentRange = 'Reduction entre 1 et 90 %.';
  static const priceNotLower = 'Le prix promo doit etre plus bas que le prix normal.';

  /// Durations offered instead of a date picker: quicker at the counter, and
  /// a merchant thinks "for a week", not "until the 14th".
  static const dealDurations = <String, Duration>{
    '1 jour': Duration(days: 1),
    '3 jours': Duration(days: 3),
    '1 semaine': Duration(days: 7),
    '2 semaines': Duration(days: 14),
    '1 mois': Duration(days: 30),
  };

  static const _months = ['janv.', 'fevr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'aout', 'sept.', 'oct.', 'nov.', 'dec.'];

  /// "14 oct." for deal end dates.
  static String shortDate(DateTime t) => '${t.day} ${_months[t.month - 1]}';

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
