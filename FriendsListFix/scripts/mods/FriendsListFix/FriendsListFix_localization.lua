--- Friends List Fix's DMF localization table for all twelve supported languages.
-- Returns a table from localization id to a table of texts by language code; DMF resolves
-- `mod:localize(id)` against it. Holds only the mod name and description. The names of the
-- Social menu and its Friends tab are taken from the game's own localization with `Localize`, so
-- they match what the player sees in the game's current language.
--
-- Loaded by DMF as `mod_localization`, as declared in `FriendsListFix.mod`.
-- module: FriendsListFix_localization
-- author: LucLeto

--- Name of the Social menu, as on its button in the system menu.
local _social_menu = "\"" .. Localize("loc_social_view_display_name") .. "\""

--- Name of the Friends tab in the Social menu.
local _friends_tab = "\"" .. Localize("loc_social_menu_roster_friends") .. "\""

return {
    mod_name = {
        en = "Friends List Fix",
        fr = "Friends List Fix",
        de = "Friends List Fix",
        it = "Friends List Fix",
        es = "Friends List Fix",
        pl = "Friends List Fix",
        ["pt-br"] = "Friends List Fix",
        ru = "Friends List Fix",
        ja = "Friends List Fix",
        ko = "Friends List Fix",
        ["zh-cn"] = "Friends List Fix",
        ["zh-tw"] = "Friends List Fix",
    },
    mod_description = {
        en = "Shows each friend only once in the " .. _friends_tab .. " tab of the " .. _social_menu .. " menu. Since Darktide 1.13.0, a player who is both your in-game friend and your Steam or Xbox friend can be listed twice. The in-game friend entry is kept, so the player options keep working; the other tabs and the game's own friends list are unchanged. A workaround until Fatshark fixes the issue.",
        fr = "Affiche chaque ami une seule fois dans l'onglet " .. _friends_tab .. " du menu " .. _social_menu .. ". Depuis Darktide 1.13.0, un joueur qui est à la fois votre ami en jeu et votre ami Steam ou Xbox peut apparaître deux fois. L'entrée de l'ami en jeu est conservée, les options du joueur continuent donc de fonctionner ; les autres onglets et la liste d'amis du jeu restent inchangés. Solution de contournement en attendant une correction de Fatshark.",
        de = "Zeigt jeden Freund im Tab " .. _friends_tab .. " des Menüs " .. _social_menu .. " nur einmal an. Seit Darktide 1.13.0 kann ein Spieler, der zugleich Freund im Spiel und Steam- oder Xbox-Freund ist, doppelt aufgeführt werden. Der Eintrag als Freund im Spiel bleibt erhalten, damit die Spieleroptionen weiter funktionieren; die anderen Tabs und die Freundesliste des Spiels selbst bleiben unverändert. Workaround, bis Fatshark das Problem behebt.",
        it = "Mostra ogni amico una sola volta nella scheda " .. _friends_tab .. " del menu " .. _social_menu .. ". Da Darktide 1.13.0, un giocatore che è sia tuo amico nel gioco sia tuo amico su Steam o Xbox può comparire due volte. Viene mantenuta la voce dell'amico nel gioco, così le opzioni del giocatore continuano a funzionare; le altre schede e l'elenco amici del gioco restano invariati. Soluzione temporanea in attesa di una correzione da parte di Fatshark.",
        es = "Muestra a cada amigo una sola vez en la pestaña " .. _friends_tab .. " del menú " .. _social_menu .. ". Desde Darktide 1.13.0, un jugador que es a la vez tu amigo en el juego y tu amigo de Steam o Xbox puede aparecer dos veces. Se conserva la entrada del amigo en el juego, así que las opciones del jugador siguen funcionando; las demás pestañas y la lista de amigos del propio juego no cambian. Solución temporal hasta que Fatshark corrija el problema.",
        pl = "Pokazuje każdego znajomego tylko raz w zakładce " .. _friends_tab .. " menu " .. _social_menu .. ". Od Darktide 1.13.0 gracz, który jest jednocześnie Twoim znajomym w grze i znajomym na Steamie lub Xboksie, może być wyświetlany dwukrotnie. Zachowywany jest wpis znajomego z gry, więc opcje gracza nadal działają; pozostałe zakładki i sama lista znajomych gry pozostają bez zmian. Obejście do czasu naprawy problemu przez Fatshark.",
        ["pt-br"] = "Mostra cada amigo apenas uma vez na aba " .. _friends_tab .. " do menu " .. _social_menu .. ". Desde o Darktide 1.13.0, um jogador que é ao mesmo tempo seu amigo no jogo e seu amigo na Steam ou no Xbox pode aparecer duas vezes. A entrada do amigo no jogo é mantida, então as opções do jogador continuam funcionando; as outras abas e a lista de amigos do próprio jogo não são alteradas. Solução temporária até que a Fatshark corrija o problema.",
        ru = "Показывает каждого друга только один раз на вкладке " .. _friends_tab .. " меню " .. _social_menu .. ". Начиная с Darktide 1.13.0, игрок, который одновременно является вашим другом в игре и другом в Steam или Xbox, может отображаться дважды. Сохраняется запись друга из игры, поэтому действия с игроком продолжают работать; другие вкладки и сам список друзей игры не изменяются. Временное решение, пока Fatshark не исправит проблему.",
        ja = _social_menu .. " メニューの " .. _friends_tab .. " タブで、各フレンドを1回だけ表示します。Darktide 1.13.0 以降、ゲーム内のフレンドであり Steam または Xbox のフレンドでもあるプレイヤーが2回表示されることがあります。ゲーム内フレンドの項目が残るため、プレイヤーの操作はそのまま使えます。他のタブやゲーム自体のフレンドリストは変わりません。Fatshark が問題を修正するまでの回避策です。",
        ko = _social_menu .. " 메뉴의 " .. _friends_tab .. " 탭에서 각 친구를 한 번만 표시합니다. Darktide 1.13.0부터 게임 내 친구이면서 Steam 또는 Xbox 친구이기도 한 플레이어가 두 번 표시될 수 있습니다. 게임 내 친구 항목이 유지되므로 플레이어 옵션은 계속 작동하며, 다른 탭과 게임 자체의 친구 목록은 변경되지 않습니다. Fatshark가 문제를 수정할 때까지 사용하는 임시 해결책입니다.",
        ["zh-cn"] = "在 " .. _social_menu .. " 菜单的 " .. _friends_tab .. " 标签页中，每位好友只显示一次。自 Darktide 1.13.0 起，同时是你的游戏内好友和 Steam 或 Xbox 好友的玩家可能会显示两次。本模组保留游戏内好友条目，因此玩家选项仍可正常使用；其他标签页和游戏本身的好友列表保持不变。这是在 Fatshark 修复该问题之前的临时方案。",
        ["zh-tw"] = "在 " .. _social_menu .. " 選單的 " .. _friends_tab .. " 分頁中，每位好友只顯示一次。自 Darktide 1.13.0 起，同時是你的遊戲內好友和 Steam 或 Xbox 好友的玩家可能會顯示兩次。本模組保留遊戲內好友項目，因此玩家選項仍可正常使用；其他分頁和遊戲本身的好友名單保持不變。這是在 Fatshark 修正該問題之前的暫時方案。",
    },
}
