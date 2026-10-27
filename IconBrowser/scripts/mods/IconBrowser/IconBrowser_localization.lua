--- Icon Browser's DMF localization table.
-- Returns a table from localization id to a table of texts by language code; DMF resolves
-- `mod:localize(id)` against it and falls back to English for a missing language. The original
-- texts (mod name and description, list columns and the window settings) and the two settings tab
-- titles cover all twelve supported languages; the other texts added with the full-screen browser
-- provide English and German. Holds the setting titles, tooltips, dropdown options and button
-- texts, which the settings menu references by id, the toolbar, category, sort, list, inspector,
-- status and shortcut hint texts, and the input legend texts, which `IconBrowser.lua` also
-- registers as global `loc_icon_browser_legend_*` keys for the game's input legend. Texts are
-- passed through `string.format` by DMF, so a literal percent sign is written as `%%`;
-- `count_format`, `preview_zoom_format`, `preview_aspect_format` and the `name_source_*` texts take
-- arguments.
--
-- Loaded by DMF as `mod_localization`, as declared in `IconBrowser.mod`, and by `IconBrowser.lua`
-- through `mod:io_dofile` for the global legend keys.
-- module: IconBrowser_localization
-- author: LucLeto
return {
    mod_name = {
        en = "Icon Browser",
        de = "Icon-Browser",
        fr = "Navigateur d'icônes",
        it = "Browser icone",
        es = "Navegador de iconos",
        pl = "Przeglądarka ikon",
        ["pt-br"] = "Navegador de ícones",
        ["ru"] = "Браузер иконок",
        ja = "アイコンブラウザー",
        ko = "아이콘 브라우저",
        ["zh-cn"] = "图标浏览器",
        ["zh-tw"] = "圖示瀏覽器",
    },
    mod_description = {
        en = "Browse Darktide UI icon materials and log their IDs and paths.",
        de = "Durchsuche Darktide-UI-Icons und protokolliere ihre IDs und Pfade.",
        fr = "Parcourez les matériaux d'icônes de l'interface de Darktide et consignez leurs ID et chemins.",
        it = "Sfoglia le risorse icona dell'interfaccia di Darktide e registra i relativi ID e percorsi.",
        es = "Explora los materiales de iconos de la interfaz de Darktide y registra sus ID y rutas.",
        pl = "Przeglądaj materiały ikon interfejsu Darktide i zapisuj ich identyfikatory oraz ścieżki.",
        ["pt-br"] = "Navegue pelos materiais de ícones da interface de Darktide e registre seus IDs e caminhos.",
        ["ru"] = "Просматривайте материалы значков интерфейса Darktide и записывайте их ID и пути.",
        ja = "Darktide の UI アイコン素材を参照し、その ID とパスを記録します。",
        ko = "Darktide UI 아이콘 머티리얼을 탐색하고 ID와 경로를 기록합니다.",
        ["zh-cn"] = "浏览 Darktide 的 UI 图标材质，并记录其 ID 和路径。",
        ["zh-tw"] = "瀏覽 Darktide 的 UI 圖示材質，並記錄其 ID 與路徑。",
    },
    column_icon = {
        en = "Icon",
        de = "Icon",
        fr = "Icône",
        it = "Icona",
        es = "Icono",
        pl = "Ikona",
        ["pt-br"] = "Ícone",
        ["ru"] = "Иконка",
        ja = "アイコン",
        ko = "아이콘",
        ["zh-cn"] = "图标",
        ["zh-tw"] = "圖示",
    },
    column_id = {
        en = "ID",
        de = "Nr",
        fr = "ID",
        it = "ID",
        es = "ID",
        pl = "ID",
        ["pt-br"] = "ID",
        ["ru"] = "ID",
        ja = "ID",
        ko = "ID",
        ["zh-cn"] = "ID",
        ["zh-tw"] = "ID",
    },
    column_path = {
        en = "Path",
        de = "Pfad",
        fr = "Chemin",
        it = "Percorso",
        es = "Ruta",
        pl = "Ścieżka",
        ["pt-br"] = "Caminho",
        ["ru"] = "Путь",
        ja = "パス",
        ko = "경로",
        ["zh-cn"] = "路径",
        ["zh-tw"] = "路徑",
    },
    open_icon_browser = {
        en = "Open Icon Browser",
        de = "Icon-Browser öffnen",
        fr = "Ouvrir le navigateur d'icônes",
        it = "Apri browser icone",
        es = "Abrir navegador de iconos",
        pl = "Otwórz przeglądarkę ikon",
        ["pt-br"] = "Abrir navegador de ícones",
        ["ru"] = "Открыть браузер иконок",
        ja = "アイコンブラウザーを開く",
        ko = "아이콘 브라우저 열기",
        ["zh-cn"] = "打开图标浏览器",
        ["zh-tw"] = "開啟圖示瀏覽器",
    },
    open_tooltip = {
        en = "Opens/closes the Icon Browser window (default: F8).",
        de = "Öffnet/schließt den Icon-Browser (Standard: F8).",
        fr = "Ouvre/ferme la fenêtre du navigateur d'icônes (par défaut : F8).",
        it = "Apre/chiude la finestra del browser icone (predefinito: F8).",
        es = "Abre/cierra la ventana del navegador de iconos (predeterminado: F8).",
        pl = "Otwiera/zamyka okno przeglądarki ikon (domyślnie: F8).",
        ["pt-br"] = "Abre/fecha a janela do navegador de ícones (padrão: F8).",
        ["ru"] = "Открывает/закрывает окно браузера иконок (по умолчанию: F8).",
        ja = "アイコンブラウザーのウィンドウを開閉します（既定: F8）。",
        ko = "아이콘 브라우저 창을 열거나 닫습니다(기본값: F8).",
        ["zh-cn"] = "打开/关闭图标浏览器窗口（默认：F8）。",
        ["zh-tw"] = "開啟/關閉圖示瀏覽器視窗（預設：F8）。",
    },
    icon_browser_scale = {
        en = "Window Size (%%)",
        de = "Fenstergröße (%%)",
        fr = "Taille de la fenêtre (%%)",
        it = "Dimensione finestra (%%)",
        es = "Tamaño de la ventana (%%)",
        pl = "Rozmiar okna (%%)",
        ["pt-br"] = "Tamanho da janela (%%)",
        ["ru"] = "Размер окна (%%)",
        ja = "ウィンドウサイズ (%%)",
        ko = "창 크기 (%%)",
        ["zh-cn"] = "窗口大小 (%%)",
        ["zh-tw"] = "視窗大小 (%%)",
    },
    size_tooltip = {
        en = "Size of the Icon Browser frame. 100%% fills the screen above the input legend.",
        de = "Größe des Icon-Browsers. 100%% füllt den Bildschirm oberhalb der Tastenlegende.",
        fr = "Taille du navigateur d'icônes. 100%% remplit l'écran au-dessus de la légende des touches.",
        it = "Dimensione del browser icone. 100%% riempie lo schermo sopra la legenda dei comandi.",
        es = "Tamaño del navegador de iconos. 100%% ocupa la pantalla por encima de la leyenda de controles.",
        pl = "Rozmiar przeglądarki ikon. 100%% wypełnia ekran nad legendą klawiszy.",
        ["pt-br"] = "Tamanho do navegador de ícones. 100%% preenche a tela acima da legenda de controles.",
        ["ru"] = "Размер браузера иконок. 100%% заполняет экран над подсказками клавиш.",
        ja = "アイコンブラウザーのサイズです。100%% で操作ガイドの上の画面全体を使います。",
        ko = "아이콘 브라우저 크기입니다. 100%%는 입력 안내 위의 화면을 가득 채웁니다.",
        ["zh-cn"] = "图标浏览器的大小。100%% 时填满按键提示上方的屏幕。",
        ["zh-tw"] = "圖示瀏覽器的大小。100%% 時填滿按鍵提示上方的螢幕。",
    },
    icon_browser_pos_x = {
        en = "Window X Position",
        de = "Fensterposition X",
        fr = "Position X de la fenêtre",
        it = "Posizione X finestra",
        es = "Posición X de la ventana",
        pl = "Pozycja X okna",
        ["pt-br"] = "Posição X da janela",
        ["ru"] = "Положение окна по X",
        ja = "ウィンドウの X 位置",
        ko = "창 X 위치",
        ["zh-cn"] = "窗口 X 位置",
        ["zh-tw"] = "視窗 X 位置",
    },
    position_x_tooltip = {
        en = "Horizontal offset of the Icon Browser window.",
        de = "Horizontaler Versatz des Icon-Browser-Fensters.",
        fr = "Décalage horizontal de la fenêtre du navigateur d'icônes.",
        it = "Offset orizzontale della finestra del browser icone.",
        es = "Desplazamiento horizontal de la ventana del navegador de iconos.",
        pl = "Poziome przesunięcie okna przeglądarki ikon.",
        ["pt-br"] = "Deslocamento horizontal da janela do navegador de ícones.",
        ["ru"] = "Горизонтальное смещение окна браузера иконок.",
        ja = "アイコンブラウザーのウィンドウの水平方向のオフセットです。",
        ko = "아이콘 브라우저 창의 가로 오프셋입니다.",
        ["zh-cn"] = "图标浏览器窗口的水平偏移。",
        ["zh-tw"] = "圖示瀏覽器視窗的水平偏移。",
    },
    icon_browser_pos_y = {
        en = "Window Y Position",
        de = "Fensterposition Y",
        fr = "Position Y de la fenêtre",
        it = "Posizione Y finestra",
        es = "Posición Y de la ventana",
        pl = "Pozycja Y okna",
        ["pt-br"] = "Posição Y da janela",
        ["ru"] = "Положение окна по Y",
        ja = "ウィンドウの Y 位置",
        ko = "창 Y 위치",
        ["zh-cn"] = "窗口 Y 位置",
        ["zh-tw"] = "視窗 Y 位置",
    },
    position_y_tooltip = {
        en = "Vertical offset of the Icon Browser window.",
        de = "Vertikaler Versatz des Icon-Browser-Fensters.",
        fr = "Décalage vertical de la fenêtre du navigateur d'icônes.",
        it = "Offset verticale della finestra del browser icone.",
        es = "Desplazamiento vertical de la ventana del navegador de iconos.",
        pl = "Pionowe przesunięcie okna przeglądarki ikon.",
        ["pt-br"] = "Deslocamento vertical da janela do navegador de ícones.",
        ["ru"] = "Вертикальное смещение окна браузера иконок.",
        ja = "アイコンブラウザーのウィンドウの垂直方向のオフセットです。",
        ko = "아이콘 브라우저 창의 세로 오프셋입니다.",
        ["zh-cn"] = "图标浏览器窗口的垂直偏移。",
        ["zh-tw"] = "圖示瀏覽器視窗的垂直偏移。",
    },
    icon_browser_move_step = {
        en = "Window Move Step",
        de = "Fenster-Bewegungsschritt",
        fr = "Pas de déplacement de la fenêtre",
        it = "Passo spostamento finestra",
        es = "Paso de movimiento de la ventana",
        pl = "Krok przesuwania okna",
        ["pt-br"] = "Passo de movimento da janela",
        ["ru"] = "Шаг перемещения окна",
        ja = "ウィンドウ移動量",
        ko = "창 이동 간격",
        ["zh-cn"] = "窗口移动步长",
        ["zh-tw"] = "視窗移動步長",
    },
    move_step_tooltip = {
        en = "How many pixels the movement keybinds move the window.",
        de = "Wie viele Pixel die Bewegungs-Tastenkürzel das Fenster verschieben.",
        fr = "Nombre de pixels de déplacement de la fenêtre par les raccourcis.",
        it = "Di quanti pixel i tasti di movimento spostano la finestra.",
        es = "Cuántos píxeles mueven la ventana los atajos de movimiento.",
        pl = "O ile pikseli skróty ruchu przesuwają okno.",
        ["pt-br"] = "Quantos pixels os atalhos de movimento deslocam a janela.",
        ["ru"] = "На сколько пикселей горячие клавиши перемещают окно.",
        ja = "移動キーでウィンドウを何ピクセル動かすかを設定します。",
        ko = "이동 키바인드로 창을 몇 픽셀 이동할지 설정합니다.",
        ["zh-cn"] = "移动快捷键每次移动窗口的像素数。",
        ["zh-tw"] = "移動快捷鍵每次移動視窗的像素數。",
    },
    move_icon_browser_left_key = {
        en = "Move Window Left",
        de = "Fenster nach links bewegen",
        fr = "Déplacer la fenêtre vers la gauche",
        it = "Sposta finestra a sinistra",
        es = "Mover ventana a la izquierda",
        pl = "Przesuń okno w lewo",
        ["pt-br"] = "Mover janela para a esquerda",
        ["ru"] = "Переместить окно влево",
        ja = "ウィンドウを左へ移動",
        ko = "창 왼쪽으로 이동",
        ["zh-cn"] = "窗口左移",
        ["zh-tw"] = "視窗左移",
    },
    move_left_tooltip = {
        en = "Moves the Icon Browser window to the left.",
        de = "Bewegt das Icon-Browser-Fenster nach links.",
        fr = "Déplace la fenêtre du navigateur d'icônes vers la gauche.",
        it = "Sposta la finestra del browser icone a sinistra.",
        es = "Mueve la ventana del navegador de iconos hacia la izquierda.",
        pl = "Przesuwa okno przeglądarki ikon w lewo.",
        ["pt-br"] = "Move a janela do navegador de ícones para a esquerda.",
        ["ru"] = "Перемещает окно браузера иконок влево.",
        ja = "アイコンブラウザーのウィンドウを左に移動します。",
        ko = "아이콘 브라우저 창을 왼쪽으로 이동합니다.",
        ["zh-cn"] = "将图标浏览器窗口向左移动。",
        ["zh-tw"] = "將圖示瀏覽器視窗向左移動。",
    },
    move_icon_browser_right_key = {
        en = "Move Window Right",
        de = "Fenster nach rechts bewegen",
        fr = "Déplacer la fenêtre vers la droite",
        it = "Sposta finestra a destra",
        es = "Mover ventana a la derecha",
        pl = "Przesuń okno w prawo",
        ["pt-br"] = "Mover janela para a direita",
        ["ru"] = "Переместить окно вправо",
        ja = "ウィンドウを右へ移動",
        ko = "창 오른쪽으로 이동",
        ["zh-cn"] = "窗口右移",
        ["zh-tw"] = "視窗右移",
    },
    move_right_tooltip = {
        en = "Moves the Icon Browser window to the right.",
        de = "Bewegt das Icon-Browser-Fenster nach rechts.",
        fr = "Déplace la fenêtre du navigateur d'icônes vers la droite.",
        it = "Sposta la finestra del browser icone a destra.",
        es = "Mueve la ventana del navegador de iconos hacia la derecha.",
        pl = "Przesuwa okno przeglądarki ikon w prawo.",
        ["pt-br"] = "Move a janela do navegador de ícones para a direita.",
        ["ru"] = "Перемещает окно браузера иконок вправо.",
        ja = "アイコンブラウザーのウィンドウを右に移動します。",
        ko = "아이콘 브라우저 창을 오른쪽으로 이동합니다.",
        ["zh-cn"] = "将图标浏览器窗口向右移动。",
        ["zh-tw"] = "將圖示瀏覽器視窗向右移動。",
    },
    move_icon_browser_up_key = {
        en = "Move Window Up",
        de = "Fenster nach oben bewegen",
        fr = "Déplacer la fenêtre vers le haut",
        it = "Sposta finestra in alto",
        es = "Mover ventana hacia arriba",
        pl = "Przesuń okno w górę",
        ["pt-br"] = "Mover janela para cima",
        ["ru"] = "Переместить окно вверх",
        ja = "ウィンドウを上へ移動",
        ko = "창 위로 이동",
        ["zh-cn"] = "窗口上移",
        ["zh-tw"] = "視窗上移",
    },
    move_up_tooltip = {
        en = "Moves the Icon Browser window up.",
        de = "Bewegt das Icon-Browser-Fenster nach oben.",
        fr = "Déplace la fenêtre du navigateur d'icônes vers le haut.",
        it = "Sposta la finestra del browser icone verso l'alto.",
        es = "Mueve la ventana del navegador de iconos hacia arriba.",
        pl = "Przesuwa okno przeglądarki ikon w górę.",
        ["pt-br"] = "Move a janela do navegador de ícones para cima.",
        ["ru"] = "Перемещает окно браузера иконок вверх.",
        ja = "アイコンブラウザーのウィンドウを上に移動します。",
        ko = "아이콘 브라우저 창을 위로 이동합니다.",
        ["zh-cn"] = "将图标浏览器窗口向上移动。",
        ["zh-tw"] = "將圖示瀏覽器視窗向上移動。",
    },
    move_icon_browser_down_key = {
        en = "Move Window Down",
        de = "Fenster nach unten bewegen",
        fr = "Déplacer la fenêtre vers le bas",
        it = "Sposta finestra in basso",
        es = "Mover ventana hacia abajo",
        pl = "Przesuń okno w dół",
        ["pt-br"] = "Mover janela para baixo",
        ["ru"] = "Переместить окно вниз",
        ja = "ウィンドウを下へ移動",
        ko = "창 아래로 이동",
        ["zh-cn"] = "窗口下移",
        ["zh-tw"] = "視窗下移",
    },
    move_down_tooltip = {
        en = "Moves the Icon Browser window down.",
        de = "Bewegt das Icon-Browser-Fenster nach unten.",
        fr = "Déplace la fenêtre du navigateur d'icônes vers le bas.",
        it = "Sposta la finestra del browser icone verso il basso.",
        es = "Mueve la ventana del navegador de iconos hacia abajo.",
        pl = "Przesuwa okno przeglądarki ikon w dół.",
        ["pt-br"] = "Move a janela do navegador de ícones para baixo.",
        ["ru"] = "Перемещает окно браузера иконок вниз.",
        ja = "アイコンブラウザーのウィンドウを下に移動します。",
        ko = "아이콘 브라우저 창을 아래로 이동합니다.",
        ["zh-cn"] = "将图标浏览器窗口向下移动。",
        ["zh-tw"] = "將圖示瀏覽器視窗向下移動。",
    },

    -- Settings added with the full-screen browser. Strings below provide en and de; DMF falls back
    -- to en for the other languages.
    icon_browser_inspector_width = {
        en = "Inspector Width (%%)",
        de = "Breite des Inspektors (%%)",
    },
    inspector_width_tooltip = {
        en = "Share of the content area used by the asset inspector on the right.",
        de = "Anteil des Inhaltsbereichs, den der Asset-Inspektor rechts einnimmt.",
    },
    icon_browser_density = {
        en = "Thumbnail Density",
        de = "Vorschaudichte",
    },
    density_tooltip = {
        en = "Size of the grid thumbnails and list rows. Also switchable in the browser toolbar.",
        de = "Größe der Rasterkacheln und Listenzeilen. Auch in der Werkzeugleiste umschaltbar.",
    },
    density_option_compact = {
        en = "Compact",
        de = "Kompakt",
    },
    density_option_normal = {
        en = "Normal",
        de = "Normal",
    },
    density_option_large = {
        en = "Large",
        de = "Groß",
    },
    icon_browser_double_click_copy = {
        en = "Double-Click Copies Path",
        de = "Doppelklick kopiert Pfad",
    },
    double_click_copy_tooltip = {
        en = "Double-clicking an asset copies its material path. A single click only selects.",
        de = "Ein Doppelklick auf ein Asset kopiert seinen Materialpfad. Ein einfacher Klick wählt nur aus.",
    },
    icon_browser_copy_hotkey = {
        en = "C Key Copies Path",
        de = "Taste C kopiert Pfad",
    },
    copy_hotkey_tooltip = {
        en = "Pressing C copies the selected material path while the search field is not focused. Ctrl+C always works.",
        de = "C kopiert den Materialpfad der Auswahl, solange das Suchfeld nicht aktiv ist. Strg+C funktioniert immer.",
    },

    -- Settings tabs, in every language like the window settings they hold
    icon_browser_group = {
        en = "Browser",
        de = "Browser",
        fr = "Navigateur",
        it = "Browser",
        es = "Navegador",
        pl = "Przeglądarka",
        ["pt-br"] = "Navegador",
        ["ru"] = "Браузер",
        ja = "ブラウザー",
        ko = "브라우저",
        ["zh-cn"] = "浏览器",
        ["zh-tw"] = "瀏覽器",
    },
    icon_browser_window_group = {
        en = "Window",
        de = "Fenster",
        fr = "Fenêtre",
        it = "Finestra",
        es = "Ventana",
        pl = "Okno",
        ["pt-br"] = "Janela",
        ["ru"] = "Окно",
        ja = "ウィンドウ",
        ko = "창",
        ["zh-cn"] = "窗口",
        ["zh-tw"] = "視窗",
    },

    -- Settings buttons
    clear_icon_browser_recent = {
        en = "Recent History",
        de = "Verlauf",
    },
    clear_recent_button = {
        en = "Clear",
        de = "Leeren",
    },
    clear_recent_tooltip = {
        en = "Empties the list of recently selected and copied assets shown by the Recent filter.",
        de = "Leert die Liste der zuletzt ausgewählten und kopierten Assets, die der Verlauf-Filter zeigt.",
    },
    clear_icon_browser_favorites = {
        en = "Favorites",
        de = "Favoriten",
    },
    clear_favorites_button = {
        en = "Hold to Clear",
        de = "Halten zum Leeren",
    },
    clear_favorites_tooltip = {
        en = "Hold the button to remove every favorite. This cannot be undone.",
        de = "Halte den Knopf gedrückt, um alle Favoriten zu entfernen. Das kann nicht rückgängig gemacht werden.",
    },
    copy_unloaded_icon_paths = {
        en = "Unloaded Icons",
        de = "Nicht geladene Icons",
    },
    copy_unloaded_button = {
        en = "Copy Paths",
        de = "Pfade kopieren",
    },
    copy_unloaded_tooltip = {
        en = "Copies the paths of all indexed icons whose material is not loaded, one per line. "
            .. "These are the icons that draw as white squares. Same as the chat command /icon_browser_unloaded.",
        de = "Kopiert die Pfade aller indizierten Icons, deren Material nicht geladen ist, einen pro Zeile. "
            .. "Das sind die Icons, die als weiße Quadrate gezeichnet werden. "
            .. "Entspricht dem Chatbefehl /icon_browser_unloaded.",
    },
    command_unloaded_description = {
        en = "Copies the paths of the icons whose material is not loaded (white squares) to the clipboard.",
        de = "Kopiert die Pfade der Icons, deren Material nicht geladen ist (weiße Quadrate), "
            .. "in die Zwischenablage.",
    },
    reset_icon_browser_position = {
        en = "Window Position",
        de = "Fensterposition",
    },
    reset_position_button = {
        en = "Reset",
        de = "Zurücksetzen",
    },
    reset_position_tooltip = {
        en = "Centres the Icon Browser again by setting the X and Y position to 0.",
        de = "Zentriert den Icon-Browser wieder, indem die X- und Y-Position auf 0 gesetzt werden.",
    },

    -- Input legend (registered as global localization keys)
    legend_select = {
        en = "Select",
        de = "Auswählen",
    },
    legend_copy_path = {
        en = "Copy Path",
        de = "Pfad kopieren",
    },
    legend_favorite = {
        en = "Favorite",
        de = "Favorit",
    },

    -- Header and toolbar
    search_placeholder = {
        en = "Search assets, names, paths or IDs...",
        de = "Assets, Namen, Pfade oder IDs suchen...",
    },
    count_format = {
        en = "%d / %d assets",
        de = "%d / %d Assets",
    },
    toolbar_category = {
        en = "Category",
        de = "Kategorie",
    },
    toolbar_sort = {
        en = "Sort",
        de = "Sortierung",
    },
    toolbar_favorites = {
        en = "Favorites",
        de = "Favoriten",
    },
    toolbar_recent = {
        en = "Recent",
        de = "Verlauf",
    },
    toolbar_clear_recent = {
        en = "Clear",
        de = "Leeren",
    },
    toolbar_view_grid = {
        en = "Grid",
        de = "Raster",
    },
    toolbar_view_list = {
        en = "List",
        de = "Liste",
    },
    toolbar_density_compact = {
        en = "S",
        de = "S",
    },
    toolbar_density_normal = {
        en = "M",
        de = "M",
    },
    toolbar_density_large = {
        en = "L",
        de = "L",
    },
    shortcut_hint = {
        en = "[Ctrl+F] Search    [Arrow keys] Navigate    [Enter] Select    [Double-click / Ctrl+C] Copy path    [Esc] Leave search / Close",
        de = "[Strg+F] Suchen    [Pfeiltasten] Navigieren    [Enter] Auswählen    [Doppelklick / Strg+C] Pfad kopieren    [Esc] Suche verlassen / Schließen",
    },

    -- Categories
    category_all = {
        en = "All Assets",
        de = "Alle Assets",
    },
    category_abilities = {
        en = "Abilities",
        de = "Fähigkeiten",
    },
    category_talents = {
        en = "Talents and Blessings",
        de = "Talente und Segnungen",
    },
    category_weapons = {
        en = "Weapons and Equipment",
        de = "Waffen und Ausrüstung",
    },
    category_hud = {
        en = "HUD",
        de = "HUD",
    },
    category_buffs = {
        en = "Buffs and Status Effects",
        de = "Buffs und Statuseffekte",
    },
    category_classes = {
        en = "Classes and Characters",
        de = "Klassen und Charaktere",
    },
    category_inventory = {
        en = "Inventory and Crafting",
        de = "Inventar und Handwerk",
    },
    category_missions = {
        en = "Missions and Objectives",
        de = "Missionen und Ziele",
    },
    category_backgrounds = {
        en = "Backgrounds and Decorations",
        de = "Hintergründe und Dekorationen",
    },
    category_other = {
        en = "Other / Uncategorized",
        de = "Sonstiges / Ohne Kategorie",
    },

    -- Sorting
    sort_name_asc = {
        en = "Name A-Z",
        de = "Name A-Z",
    },
    sort_name_desc = {
        en = "Name Z-A",
        de = "Name Z-A",
    },
    sort_path_asc = {
        en = "Resource Path A-Z",
        de = "Ressourcenpfad A-Z",
    },
    sort_path_desc = {
        en = "Resource Path Z-A",
        de = "Ressourcenpfad Z-A",
    },
    sort_category_asc = {
        en = "Category A-Z",
        de = "Kategorie A-Z",
    },
    sort_category_desc = {
        en = "Category Z-A",
        de = "Kategorie Z-A",
    },
    sort_index_asc = {
        en = "Browser Index Ascending",
        de = "Browser-Index aufsteigend",
    },
    sort_index_desc = {
        en = "Browser Index Descending",
        de = "Browser-Index absteigend",
    },
    -- Short forms shown on the sort button; the menu lists the full names above.
    sort_short_name_asc = {
        en = "Name A-Z",
        de = "Name A-Z",
    },
    sort_short_name_desc = {
        en = "Name Z-A",
        de = "Name Z-A",
    },
    sort_short_path_asc = {
        en = "Path A-Z",
        de = "Pfad A-Z",
    },
    sort_short_path_desc = {
        en = "Path Z-A",
        de = "Pfad Z-A",
    },
    sort_short_category_asc = {
        en = "Category A-Z",
        de = "Kategorie A-Z",
    },
    sort_short_category_desc = {
        en = "Category Z-A",
        de = "Kategorie Z-A",
    },
    sort_short_index_asc = {
        en = "Index 1-9",
        de = "Index 1-9",
    },
    sort_short_index_desc = {
        en = "Index 9-1",
        de = "Index 9-1",
    },
    sort_marker_ascending = {
        en = "(A-Z)",
        de = "(A-Z)",
    },
    sort_marker_descending = {
        en = "(Z-A)",
        de = "(Z-A)",
    },
    sort_marker_numeric_ascending = {
        en = "(1-9)",
        de = "(1-9)",
    },
    sort_marker_numeric_descending = {
        en = "(9-1)",
        de = "(9-1)",
    },

    -- List columns (column_id and column_path are defined above)
    column_preview = {
        en = "Preview",
        de = "Vorschau",
    },
    column_name = {
        en = "Name",
        de = "Name",
    },
    column_category = {
        en = "Category",
        de = "Kategorie",
    },

    -- Browser states
    empty_results = {
        en = "No assets match the current search and filters.",
        de = "Keine Assets entsprechen der aktuellen Suche und den Filtern.",
    },
    empty_favorites = {
        en = "No favorites yet. Select an asset and press F or use Add Favorite.",
        de = "Noch keine Favoriten. Wähle ein Asset und drücke F oder nutze Als Favorit.",
    },
    empty_recent = {
        en = "No recent assets yet. Selected and copied assets appear here.",
        de = "Noch kein Verlauf. Ausgewählte und kopierte Assets erscheinen hier.",
    },
    preview_unavailable = {
        en = "Preview unavailable",
        de = "Vorschau nicht verfügbar",
    },
    preview_unavailable_short = {
        en = "NO PREVIEW",
        de = "KEINE VORSCHAU",
    },
    preview_not_loaded = {
        en = "Not available - the material is not loaded",
        de = "Nicht verfügbar - das Material ist nicht geladen",
    },
    preview_not_loaded_short = {
        en = "NOT AVAILABLE",
        de = "NICHT VERFÜGBAR",
    },
    preview_loading = {
        en = "Loading - waiting for a game package",
        de = "Lädt - warte auf ein Spielpaket",
    },
    preview_loading_short = {
        en = "LOADING...",
        de = "LÄDT...",
    },

    -- Inspector
    inspector_no_selection = {
        en = "Select an asset to inspect its preview and resource path.",
        de = "Wähle ein Asset aus, um Vorschau und Ressourcenpfad zu sehen.",
    },
    field_path = {
        en = "Material path",
        de = "Materialpfad",
    },
    field_filename = {
        en = "Filename",
        de = "Dateiname",
    },
    field_id = {
        en = "Browser ID",
        de = "Browser-ID",
    },
    field_category = {
        en = "Category",
        de = "Kategorie",
    },
    field_name_source = {
        en = "Name",
        de = "Name",
    },
    field_preview = {
        en = "Preview",
        de = "Vorschau",
    },
    field_size = {
        en = "Size",
        de = "Größe",
    },
    field_used_in = {
        en = "Used in",
        de = "Verwendet in",
    },
    field_items = {
        en = "Items",
        de = "Gegenstände",
    },
    name_source_localized = {
        en = "Localized (%s)",
        de = "Lokalisiert (%s)",
    },
    name_source_definition = {
        en = "Game definition key (%s)",
        de = "Schlüssel der Spieldefinition (%s)",
    },
    name_source_filename = {
        en = "Derived from the filename",
        de = "Aus dem Dateinamen abgeleitet",
    },
    name_source_more_uses = {
        en = "(+%d more uses)",
        de = "(+%d weitere Verwendungen)",
    },
    preview_status_available = {
        en = "Available",
        de = "Verfügbar",
    },
    preview_status_failed = {
        en = "Failed to render - the path can still be copied",
        de = "Darstellung fehlgeschlagen - der Pfad kann trotzdem kopiert werden",
    },
    preview_status_not_loaded = {
        en = "Material not loaded - draws as a white square",
        de = "Material nicht geladen - wird als weißes Quadrat gezeichnet",
    },
    preview_status_loading = {
        en = "Not loaded yet - a game package is still loading",
        de = "Noch nicht geladen - ein Spielpaket lädt noch",
    },
    size_unknown = {
        en = "Not exposed by the engine",
        de = "Von der Engine nicht geliefert",
    },
    size_drawn_at = {
        en = "Drawn at %s by the game",
        de = "Vom Spiel in %s gezeichnet",
    },
    used_in_none = {
        en = "Not named in the game scripts",
        de = "In den Spielskripten nicht genannt",
    },
    more_format = {
        en = "(+%d more)",
        de = "(+%d weitere)",
    },
    preview_background_dark = {
        en = "BG: Dark",
        de = "BG: Dunkel",
    },
    preview_background_light = {
        en = "BG: Light",
        de = "BG: Hell",
    },
    preview_background_checker = {
        en = "BG: Checker",
        de = "BG: Schach",
    },
    preview_zoom_fit = {
        en = "Zoom: Fit",
        de = "Zoom: Passend",
    },
    preview_zoom_format = {
        en = "Zoom: %dx",
        de = "Zoom: %dx",
    },
    preview_aspect_format = {
        en = "Aspect: %s",
        de = "Format: %s",
    },
    preview_aspect_auto = {
        en = "Aspect: Auto",
        de = "Format: Auto",
    },
    action_copy_path = {
        en = "Copy Material Path",
        de = "Materialpfad kopieren",
    },
    action_copy_filename = {
        en = "Copy Filename",
        de = "Dateiname kopieren",
    },
    action_copy_lua_string = {
        en = "Copy Lua String",
        de = "Lua-String kopieren",
    },
    action_copy_ui_snippet = {
        en = "Copy UI Snippet",
        de = "UI-Snippet kopieren",
    },
    action_copy_sources = {
        en = "Copy Sources",
        de = "Quellen kopieren",
    },
    action_favorite_add = {
        en = "Add Favorite",
        de = "Als Favorit",
    },
    action_favorite_remove = {
        en = "Remove Favorite",
        de = "Favorit entfernen",
    },

    -- Status messages
    status_copied_path = {
        en = "Material path copied",
        de = "Materialpfad kopiert",
    },
    status_copied_filename = {
        en = "Filename copied",
        de = "Dateiname kopiert",
    },
    status_copied_lua_string = {
        en = "Lua string copied",
        de = "Lua-String kopiert",
    },
    status_copied_ui_snippet = {
        en = "Lua UI snippet copied",
        de = "Lua-UI-Snippet kopiert",
    },
    status_copied_sources = {
        en = "Source references copied",
        de = "Quellverweise kopiert",
    },
    status_copy_failed = {
        en = "Copy failed",
        de = "Kopieren fehlgeschlagen",
    },
    status_favorite_added = {
        en = "Added to favorites",
        de = "Zu Favoriten hinzugefügt",
    },
    status_favorite_removed = {
        en = "Removed from favorites",
        de = "Aus Favoriten entfernt",
    },
    status_recent_cleared = {
        en = "Recent history cleared",
        de = "Verlauf geleert",
    },
}
