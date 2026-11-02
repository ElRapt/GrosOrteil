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
Seuls les joueurs à 60 mètres (convention du client), dans le même espace,
sont affichés dans le résumé ; les bulles nécessitent une plaque accessible.
Cela dépend du canal de royaume/faction et des positions accessibles : la
détection est suspendue en combat, dans les instances PvE/PvP et si WoW masque
les coordonnées. Les quartiers et intérieurs de logement sont reconnus
séparément : ils ne sont plus bloqués simplement parce qu'ils sont instanciés.
Il s'agit d'une approximation
horizontale, sans garantie de hauteur ou de ligne de vue identique au vrai `/say`.
Les déplacements de l'émetteur sont reflétés au prochain signal. Dans le monde
ouvert, des phases ou des couches superposées restent indiscernables.

**Logement :** le calculateur de distance essaie les coordonnées publiques
disponibles. Pour la position du joueur, une conversion de la position sur la
carte sert de secours si les coordonnées d'unité sont absentes. Si les deux
sont indisponibles, la mesure reste indisponible. Le point mémorisé est effacé
en quittant le monde et ne peut pas être comparé dans une autre maison.

Les indicateurs `/say` de logement exigent cette mise à jour des deux côtés,
le même quartier ou le même intérieur de maison, et le même système de
coordonnées. L'identifiant technique du quartier/de la maison accompagne le
statut pour éviter les correspondances entre copies ayant les mêmes coordonnées.
Un joueur à l'intérieur ne voit donc pas les indicateurs des joueurs à l'extérieur.
Les messages extérieurs restent compatibles avec les anciennes versions.
La disponibilité réelle des coordonnées dépend toujours du client WoW : cette
modification retire le blocage de GrosOrteil, elle ne débloque pas les API de Blizzard.

Pour diagnostiquer un cas en jeu : `/go typingdebug` indique notamment
`SAY position: available`, `housing_context` (identité du logement en attente),
`unavailable`, `restricted`, `instance` ou `combat`, sans afficher vos coordonnées
ni l'identifiant du logement. `/go typingdebug off` arrête le diagnostic.

Le texte du brouillon n'est jamais transmis ni enregistré. Les positions de
proximité sont envoyées aux membres du canal dédié et expirent avec le statut.
Désactiver **Saisie** arrête les signaux et quitte ce canal. Les autres canaux
non listés sont ignorés. Les plaques interdites par WoW ne sont pas modifiées ;
le résumé reste disponible pour le groupe et les chuchotements.

Voir [les tests et la vérification en jeu](tests/README.md).

