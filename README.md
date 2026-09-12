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
