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
  // "Djassa Pro": the merchant app, told apart from the customer app
  // ("Djassa") on a phone that has both.
  static const signInTitle = 'Djassa Pro';
  static const signInSubtitle = 'Espace marchand';
  static const signInPhoneLabel = 'Numero de telephone';
  static const signInPhoneHint = '07 12 34 56 78';
  static const signInPhoneHelper = 'Votre numero de gerant ou de caissier. Code par SMS.';
  static const signInSendCode = 'Recevoir le code';
  static const signInCodeSentTo = 'Code envoye par SMS au';
  static const signInCodeLabel = 'Code a 6 chiffres';
  static const signInResendCode = 'Renvoyer le code';
  static const signInChangeNumber = 'Changer de numero';
  static const signIn = 'Se connecter';
  static const signingIn = 'Connexion...';
  static const signOut = 'Se deconnecter';

  // Account and recovery
  static const account = 'Mon compte';
  static const accountNumber = 'Numero du compte';
  static const changeNumber = 'Changer de numero';
  static const changeNumberHint = 'Gardez votre commerce et vos ventes sur un nouveau numero.';
  static const changeNumberIntro = 'Il faut les deux SIM : un code arrive sur l\'ancien numero, un autre sur le nouveau.';
  static const newPhone = 'Nouveau numero';
  static const sendCodes = 'Recevoir les codes';
  static const oldNumberCode = 'Code recu sur l\'ancien numero';
  static const newNumberCode = 'Code recu sur le nouveau numero';
  static const confirmChange = 'Changer de numero';
  static const numberChanged = 'Votre compte est maintenant sur le';
  static const signOutOthers = 'Deconnecter les autres telephones';
  static const signOutOthersHint = 'Telephone perdu ou vole : il perd l\'acces dans l\'heure. Les ventes de ce telephone-ci restent.';
  static const signOutOthersConfirm = 'Deconnecter tous les autres telephones ?';
  static const signOutOthersDone = 'Les autres telephones sont deconnectes.';
  static const lostNumber = 'Numero perdu ?';
  static const lostNumberTitle = 'Recuperer mon commerce';
  static const lostNumberIntro = 'Votre ancien numero ne marche plus ? Verifiez votre nouveau numero, puis dites-nous qui vous etes. Djassa vous appelle et transfere votre commerce.';
  static const oldPhone = 'Ancien numero';
  static const recoveryDetails = 'Pour vous reconnaitre';
  static const recoveryDetailsHint = 'Nom du commerce, quartier, votre nom...';
  static const sendRequest = 'Envoyer la demande';
  static const requestSent = 'Demande envoyee';
  static const backToSignIn = 'Retour a la connexion';
  static const continueLabel = 'Continuer';

  // Joining Djassa as a merchant
  static const becomePartner = 'Pas encore commercant Djassa ? Inscrivez votre commerce';
  static const partnerTitle = 'Inscrire mon commerce';
  static const partnerIntro =
      'Laissez-nous vos informations : un agent Djassa vous appelle pour finaliser l\'inscription. Ce numero deviendra votre connexion a Djassa Pro.';
  static const partnerPhone = 'Votre numero';
  static const partnerContactName = 'Votre nom';
  static const partnerShopName = 'Nom du commerce';
  static const partnerCategory = 'Type de commerce';
  static const partnerCommune = 'Commune ou quartier';
  static const partnerAddress = 'Adresse ou repere (facultatif)';
  static const partnerWallet = 'Les clients vous paient avec';
  static const partnerWalletNone = 'Pas de mobile money pour l\'instant';
  static const partnerNotes = 'Autre chose a nous dire (facultatif)';
  static const partnerMissing = 'Remplissez votre nom, le nom du commerce et la commune.';
  // Keys are the backend's (app/api/customer.py CATEGORIES).
  static const partnerCategories = {
    'maquis': 'Maquis, restaurant',
    'superette': 'Superette, boutique',
    'pharmacy': 'Pharmacie',
    'mode': 'Mode',
    'beaute': 'Beaute, coiffure',
    'telephonie': 'Telephonie',
  };
  static const partnerWallets = {'wave': 'Wave', 'orange': 'Orange Money', 'mtn': 'MTN MoMo', 'moov': 'Moov Money'};
  static const signOutConfirm = 'Se deconnecter ?';
  static const signOutConfirmHint = 'Les ventes non envoyees restent sur ce telephone.';

  // Home
  static const today = "Aujourd'hui";
  static const salesToday = 'ventes du jour';
  static const noSalesYet = 'Aucune vente enregistree aujourd\'hui.';
  static const noSalesYetHint = 'Vos ventes du jour et leur montant total apparaitront ici.';
  static const recordSale = 'Enregistrer une vente';

  // Pilot: end-of-day estimate (the denominator of "share of sales recorded").
  static const dailyReportQuestion = "Aujourd'hui, combien de ventes environ ?";
  static const dailyReportHint = 'Toutes vos ventes, meme celles pas notees ici. Une seule reponse par jour.';
  static const dailyReportThanks = 'Merci ! A demain.';
  static const recentSales = 'Dernieres ventes';
  static const seeAll = 'Tout voir';
  static const menu = 'Menu';
  static const greeting = 'Bonjour';
  static const homeTagline = 'Espace marchand';

  // Sync status. The merchant needs to know what has left the phone and what
  // has not, in words, not a spinner.
  static const allSent = 'Tout est envoye';
  static const waitingToSend = 'en attente d\'envoi';
  static const waitingToSendOne = '1 vente en attente d\'envoi';
  static const sendNow = 'Envoyer maintenant';
  static const sending = 'Envoi...';
  static const sentOk = 'Ventes envoyees';
  static const noConnection = 'Pas de connexion. Les ventes restent sur le telephone.';
  static const needsAttention = 'a verifier';
  static const needsAttentionOne = '1 vente a verifier';

  // Record a sale
  static const amount = 'Montant';
  static const amountHint = 'Ex : 1500';
  static const saleType = 'Type';
  static const customerOptional = 'Client (optionnel)';
  static const customerHint = 'Numero de telephone';
  static const customerEarnsHint = 'Avec son numero, le client gagne des points chez vous.';
  static const customerPhoneInvalid = 'Numero invalide : 10 chiffres, par ex. 07 12 34 56 78.';
  static const pointsShort = 'pts';
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
  static const loadFailed = 'Impossible de charger. Verifiez votre connexion.';

  // Getting paid by QR: the customer scans with the Djassa app and pays from
  // their own wallet, straight to the merchant's.
  static const collect = 'Encaisser';
  static const collectIntro = 'Entrez le montant, puis montrez le QR code au client.';
  static const showQr = 'Afficher le QR code';
  static const creatingQr = 'Creation du QR code...';
  static const scanToPay = 'Le client scanne ce QR code avec l\'application Djassa';
  static const orTypeCode = 'ou tape le code';
  static const expiresIn = 'Expire dans';
  static const waitingForPayment = 'En attente du paiement...';
  static const customerPaying = 'Le client est en train de payer...';
  static const paid = 'Paye';
  static const paidWith = 'Paye avec';
  static const customerEarned = 'points gagnes par le client';
  static const newCollect = 'Nouvel encaissement';
  static const cancelQr = 'Annuler ce QR code';
  static const qrExpired = 'QR code expire. Creez-en un nouveau.';
  static const qrCancelled = 'QR code annule.';
  static const amountRange = 'Montant entre 100 F et 2 000 000 F.';
  static const paymentNeedsConnection = 'Connexion necessaire pour encaisser par QR code.';
  static const moneyGoesToYou = 'L\'argent va directement sur votre portefeuille mobile money. Djassa ne le garde jamais.';
  static const fixedQr = 'Mon QR code fixe';
  static const fixedQrIntro =
      'A imprimer et coller au comptoir. Le client le scanne et tape lui-meme le montant.';
  static const printHint = 'Faites une capture d\'ecran pour l\'imprimer.';

  // Shop position, so customers get directions ("Itineraire") to the shop.
  static const shopLocation = 'Position du commerce';
  static const shopLocationIntro =
      'Enregistrez la position de votre commerce : vos clients auront l\'itineraire '
      'jusqu\'a vous dans l\'application Djassa.';
  static const shopLocationSet = 'Position enregistree';
  static const shopLocationNotSet = 'Pas encore de position';
  static const shopLocationNotSetHint = 'Vos clients ne voient que l\'adresse ecrite, souvent imprecise.';
  static const precision = 'Precision';
  static const recordHere = 'Enregistrer la position ici';
  static const updateHere = 'Mettre a jour avec la position actuelle';
  static const inShopQuestion = 'Etes-vous dans votre commerce en ce moment ?';
  static const inShopQuestionHint =
      'La position actuelle du telephone deviendra l\'adresse de votre commerce pour vos clients.';
  static const yesInShop = 'Oui, je suis dans mon commerce';
  static const notNow = 'Non, plus tard';

  // Shop photos and videos
  static const mediaMenu = 'Photos et videos';
  static const mediaTitle = 'Photos et videos';
  static const mediaIntro =
      'Montrez votre commerce : 10 photos et 3 videos de 60 secondes maximum. Djassa les allege pour que vos clients les voient meme avec peu de credit.';
  static const mediaAddPhoto = 'Ajouter une photo';
  static const mediaTakePhoto = 'Prendre une photo';
  static const mediaAddVideo = 'Ajouter une video';
  static const mediaPhotos = 'photos';
  static const mediaVideos = 'videos';
  static const mediaEmpty = 'Aucune photo pour l\'instant. Une photo de la devanture aide vos clients a vous trouver.';
  static const mediaUploading = 'Envoi en cours... gardez l\'application ouverte.';
  static const mediaProcessing = 'Video en preparation. Tirez vers le bas pour actualiser.';
  static const mediaFailed = 'Echec';
  static const mediaDelete = 'Supprimer';
  static const mediaDeleteQuestion = 'Supprimer ce media ?';
  static const mediaPutFirst = 'Mettre en premier';
  static const mediaHeavyTitle = 'Video lourde';
  static const mediaHeavyHint = 'Cette video pese';
  static const mediaHeavyAdvice = 'Envoyez-la plutot en Wi-Fi pour ne pas consommer votre credit.';
  static const mediaSendAnyway = 'Envoyer quand meme';
  static const mediaLimitReached = 'Limite atteinte : supprimez-en un d\'abord.';

  // Wave: the merchant's own Wave Business account (pilot).
  static const waveMenu = 'Connecter Wave';

  // Team: cashiers the owner adds (lib/features/staff_screen.dart)
  static const team = 'Mon equipe';
  static const teamIntro = 'Vos caissiers enregistrent les ventes, encaissent et donnent les points, chacun sur son telephone. Wave, bons plans, photos et position restent a vous.';
  static const addCashier = 'Ajouter un caissier';
  static const addCashierHint = 'Il recoit un SMS et se connecte a Djassa Pro avec ce numero.';
  static const cashierPhone = 'Numero du caissier';
  static const cashierName = 'Prenom (facultatif)';
  static const cashierPhoneNeeded = 'Entrez le numero du caissier';
  static const cashierAdded = 'Caissier ajoute. Il peut se connecter.';
  static const cashierInvited = 'Pas encore connecte';
  static const cashierActive = 'Connecte';
  static const removeCashier = 'Retirer';
  static const removeCashierConfirm = 'Retirer ce caissier ?';
  static const removeCashierHint = 'Il perd l\'acces tout de suite, sur tous ses telephones. Ses ventes restent dans vos comptes.';
  static const cashierRemoved = 'Caissier retire.';
  static const noCashiers = 'Pas encore de caissier';
  static const noCashiersHint = 'Ajoutez les personnes qui tiennent la caisse.';
  static const teamNeedsConnection = 'Il faut une connexion pour gerer l\'equipe.';
  static const add = 'Ajouter';
  // Shown to a cashier, under the greeting.
  static const cashierBadge = 'Caissier';
  static const waveTitle = 'Wave';
  static const waveIntro =
      'Reliez votre compte Wave Business : chaque client qui paie votre QR Wave habituel gagne ses points Djassa automatiquement. Vos clients ne changent rien. Djassa ne touche jamais l\'argent.';
  static const waveStart = 'Commencer';
  static const waveSteps = [
    'Ouvrez business.wave.com sur un ordinateur ou un telephone, section Developpeur, puis Webhooks.',
    'Ajoutez un webhook avec l\'adresse ci-dessous. Choisissez "Secret de signature" et cochez l\'evenement merchant.payment_received.',
    'Wave affiche un secret de signature : collez-le ci-dessous et enregistrez.',
  ];
  static const waveSecretLabel = 'Secret de signature du webhook';
  static const waveSecretMissing = 'Collez le secret de signature donne par Wave.';
  static const waveSave = 'Enregistrer';
  static const waveSaved = 'Enregistre';
  static const wavePointsOn = 'Points Wave actifs : vos clients Wave gagnent leurs points automatiquement.';
  static const wavePointsOff = 'Pas encore actif : ajoutez le webhook dans Wave, puis collez le secret.';
  static const waveLastEvent = 'Dernier message de Wave :';
  static const waveWebhookAddress = 'Adresse du webhook a coller dans Wave';
  static const waveSafetyPoints =
      'Le secret de signature sert seulement a verifier que les messages viennent de Wave. Il ne permet ni de creer ni de deplacer un paiement.';
  static const waveReplaceSecret = 'Changer le secret';

  // Optional: paying the shop from inside the Djassa app.
  static const wavePayTitle = 'Paiement dans l\'app Djassa (facultatif)';
  static const wavePayIntro =
      'Sans cela, vos clients paient votre QR Wave comme d\'habitude et gagnent leurs points. Avec, ils peuvent aussi payer depuis l\'app Djassa. Il faut alors une cle API Wave.';
  static const wavePaySteps = [
    'Dans business.wave.com, section Developpeur, Cles API : creez une cle en cochant UNIQUEMENT "Checkout API".',
    'Dans votre webhook Wave, cochez aussi checkout.session.completed et checkout.session.payment_failed.',
    'Collez la cle ci-dessous.',
  ];
  static const waveScopeWarning =
      'Cochez uniquement "Checkout API". Ne cochez JAMAIS "Payout API" (envoi d\'argent) : avec cette permission, la cle pourrait vider votre compte si elle etait volee.';
  static const waveKeyLabel = 'Cle API Wave';
  static const waveKeyMissing = 'Collez la cle API Wave complete.';
  static const wavePayOn = 'Paiement dans l\'app actif, cle';
  static const wavePaySafety =
      'La cle permet de creer des paiements vers votre compte, pas de retirer de l\'argent. Elle est chiffree chez Djassa et vous pouvez la revoquer a tout moment dans Wave.';
  static const waveDisconnect = 'Deconnecter Wave';
  static const waveDisconnectQuestion = 'Deconnecter Wave ?';
  static const waveDisconnectHint =
      'Djassa oubliera le secret et la cle. Supprimez aussi le webhook et revoquez la cle dans le portail Wave Business.';
  static const copy = 'Copier';
  static const copied = 'Copie';
  static const locating = 'Recherche de la position...';
  static const locatingHint = 'Restez dans le commerce, pres d\'une porte ou d\'une fenetre.';
  static const useThisPosition = 'Utiliser cette position ?';
  static const useThisPositionHint = 'Precision du GPS';
  static const retryLocate = 'Reessayer';
  static const locationSaved = 'Position enregistree. Vos clients ont maintenant l\'itineraire.';
  static const locationServiceOff = 'La localisation est desactivee. Activez-la dans les parametres du telephone.';
  static const locationDenied = 'Djassa n\'a pas l\'autorisation d\'utiliser la position.';
  static const openSettings = 'Ouvrir les parametres';
  static const locationTooVague =
      'Position trop imprecise. Approchez-vous d\'une porte ou d\'une fenetre, puis reessayez.';
  static const locationNeedsConnection = 'Connexion necessaire pour enregistrer la position.';
  static const meters = 'm';

  // Customer points at the counter.
  static const customerPoints = 'Points client';
  static const customerPointsIntro =
      'Entrez le numero du client pour voir ses points chez vous et lui donner une recompense.';
  static const phoneLabel = 'Numero du client';
  static const lookUp = 'Voir les points';
  static const lookingUp = 'Recherche...';
  static const pointsHere = 'points chez vous';
  static const noRewards = 'Aucune recompense configuree pour votre commerce.';
  static const give = 'Donner';
  static const giving = 'Envoi...';
  static const pointsMissing = 'encore';
  static const giveConfirm = 'Donner cette recompense ?';
  static const giveConfirmHint = 'Les points seront retires du compte du client.';
  static const voucherTitle = 'Recompense donnee';
  static const voucherCode = 'Code';
  static const remainingPoints = 'Points restants';
  static const ok = 'OK';
  static const pointsNeedConnection = 'Connexion necessaire pour voir les points du client.';
  static const notEnoughPoints = 'Pas assez de points pour cette recompense.';

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
  static const maxDealsReached = 'Vous avez deja 5 bons plans en cours.';

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

  /// "14:32" for a sale's time in the recent list.
  static String shortTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

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
