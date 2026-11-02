# GrosOrteil

## Indicateurs de saisie

Le bouton **Saisie** du pied de la fenêtre `/go` active ou désactive ensemble
l'envoi et l'affichage des indicateurs. Le choix est enregistré par personnage ;
la fonctionnalité est activée par défaut. Les deux joueurs doivent utiliser une
version de GrosOrteil qui la prend en charge.

- Une petite bulle fixe, de la couleur du canal, apparaît au-dessus des plaques
  de nom disponibles. Activez les plaques de nom amicales pour les voir.
- `/party`, `/raid` et le chat d'instance transmettent le statut aux destinataires
  du canal, sans limite de distance. `/whisper` le transmet uniquement au personnage
  destinataire ; les conversations Battle.net ne sont pas prises en charge.
- Un résumé sur une ligne au-dessus du chat reste lisible avec de nombreux
  participants. Il affiche le nom TRP connu, sinon le nom du personnage, et
  prend la couleur du canal (rose pour les chuchotements). Survolez-le pour
  consulter les noms TRP et leurs canaux. Si plusieurs canaux sont utilisés
  simultanément, le total reste blanc et chaque nom survolé garde la couleur
  de son canal.
- Le statut s'arrête à l'envoi, à la fermeture ou après 8 secondes sans modification.
  Une déconnexion ou un arrêt perdu ne laisse pas d'indicateur au-delà de 7 secondes
  après le dernier signal reçu. Les signaux actifs sont renouvelés toutes les
  3 secondes, pas à chaque frappe.

**Limites de proximité sur Retail :** WoW ne permet pas de messages d'addon via
`SAY`. GrosOrteil utilise donc un canal temporaire dédié, `GrosOrteilTyping`,
avec la position horizontale du personnage pendant sa saisie en `/say`.
Seuls les joueurs à 60 mètres (convention du client), dans le même espace et
avec une plaque de nom visible sont affichés. Cela dépend du canal de royaume/
faction et des positions accessibles : la détection est désactivée en combat,
en instance ou si WoW masque les coordonnées. Il s'agit d'une approximation
horizontale, sans garantie de hauteur ou de ligne de vue identique au vrai `/say`.
Les déplacements de l'émetteur sont reflétés au prochain signal.

Le texte du brouillon n'est jamais transmis ni enregistré. Les positions de
proximité sont envoyées aux membres du canal dédié et expirent avec le statut.
Désactiver **Saisie** arrête les signaux et quitte ce canal. Les autres canaux
non listés sont ignorés. Les plaques interdites par WoW ne sont pas modifiées ;
le résumé reste disponible pour le groupe et les chuchotements.

Voir [les tests et la vérification en jeu](tests/README.md).


## Cambuse et montures (2.6)

- **Cambuse : PV** ajoute 25 PV et 25 PV maximum.
- **Cambuse : Attaque** ajoute 10 en attaque (CaC et distance) et 10 en esquive.
- **Cambuse : Régénération** ajoute 2 à la régénération par tour. Utilisez le
  bouton de régénération pour recevoir le soin ; **Tour suivant** fait seulement
  avancer les effets à durée limitée. Les anciens bonus Cambuse actifs sont mis à jour au chargement.

Dans `/go` → **Familier** → **Montures**, invoquez une monture dans WoW pour
créer sa fiche. Chaque monture du journal conserve son nom, ses PV, son armure
et son esquive. **Précédente / Suivante** parcourent les fiches déjà créées ;
**Actuelle** revient à la monture sortie. Une fiche générique couvre les
montures que le journal ne peut pas identifier.

**Utiliser mon familier** partage les statistiques et les PV du familier :
les dégâts et soins appliqués depuis l'une des deux fiches affectent le même
compagnon. Désactiver ce lien retrouve les valeurs propres à la monture.
Les actions, les restaurations du pied de fenêtre et l'annulation fonctionnent
sur la fiche affichée. Les événements des montures figurent dans l'historique
**Familier**, identifiés par `[Monture]` lorsqu'elles sont indépendantes.

Tant que WoW indique que le personnage est en selle, son esquive effective est
nulle. Sa valeur de base est conservée et redevient disponible à pied. La monture
garde sa propre esquive ; les dégâts du cavalier ne lui sont pas transférés.

Au survol d'un cavalier utilisant cette version, les PV, l'armure et l'esquive de
sa monture apparaissent au-dessus de son profil de monture TRP3, s'il existe.
Les barres du cavalier restent visibles à côté du profil du personnage pour
éviter le chevauchement. Sans profil de monture, les statistiques s'empilent
au-dessus des barres du cavalier. TRP3 reste facultatif. Seule la fiche de la
monture actuellement sortie est synchronisée, pas l'ensemble des fiches.

## Affixes personnalisés (2.7)

Dans **Affixes** → **Affixes personnalisés**, cliquez sur **+ Nouvel affixe**.
Donnez-lui un nom, choisissez sa couleur et ajoutez autant de statistiques
différentes que nécessaire avec **+ Statistique**. Chaque ligne possède sa
propre valeur, positive ou négative ; les décimales sont acceptées. Les choix
sont les PV maximum, l'armure, l'armure véritable, l'armure temporaire, l'esquive,
l'attaque au corps à corps, l'attaque à distance, la régénération par tour et
la perception (personnage uniquement). Un effet de PV maximum modifie aussi
les PV actuels, dans les limites habituelles de la fiche.

La durée est illimitée par défaut. Activez **Durée : limitée** pour choisir
de 1 à 9999 tours, partagés par tous les effets de cet affixe. **Enregistrer**
crée l'affixe sans l'activer. Cliquez ensuite sur sa carte pour appliquer ou
retirer ses effets. **Tour suivant** avance les compteurs du personnage et du
familier ; à zéro, l'affixe se désactive et reste disponible pour une prochaine
utilisation. La régénération reste une action manuelle.

Les créations restent séparées de Cambuse et des élixirs. Le personnage et le
familier conservent chacun leurs créations et leurs activations, y compris
après `/reload`. Une monture liée au familier partage ses statistiques modifiées.
**Modifier** permet de changer le nom et la couleur d'un affixe actif sans
relancer sa durée. Désactivez-le pour changer ses statistiques ou sa durée.
**Supprimer** retire aussi ses effets actifs. Création, modification, suppression,
activation et passage de tour sont compatibles avec **Annuler / Rétablir**.
Seules les statistiques résultantes sont synchronisées avec le groupe, pas
les définitions personnalisées.
