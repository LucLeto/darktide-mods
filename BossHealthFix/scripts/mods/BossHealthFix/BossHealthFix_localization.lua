--- Boss Health Fix's DMF localization table for all twelve supported languages.
-- Returns a table from localization id to a table of texts by language code; DMF resolves
-- `mod:localize(id)` against it. Holds only the mod name and description. Diagnostic log lines are
-- developer output and stay in English.
--
-- Loaded by DMF as `mod_localization`, as declared in `BossHealthFix.mod`.
-- module: BossHealthFix_localization
-- author: LucLeto
return {
    mod_name = {
        en = "Boss Health Fix",
        fr = "Boss Health Fix",
        de = "Boss Health Fix",
        it = "Boss Health Fix",
        es = "Boss Health Fix",
        pl = "Boss Health Fix",
        ["pt-br"] = "Boss Health Fix",
        ru = "Boss Health Fix",
        ja = "Boss Health Fix",
        ko = "Boss Health Fix",
        ["zh-cn"] = "Boss Health Fix",
        ["zh-tw"] = "Boss Health Fix",
    },
    mod_description = {
        en = "Prevents a boss health bar crash that can occur, mostly as a non-host client, when several bosses die or despawn in quick succession. Stale boss entries are removed before the vanilla boss health bar updates; living bosses and the vanilla bars are unchanged. A defensive workaround until Fatshark fixes the issue.",
        fr = "Empêche un plantage de la barre de vie des boss qui peut survenir, surtout en tant que client non hôte, lorsque plusieurs boss meurent ou disparaissent en peu de temps. Les entrées de boss obsolètes sont retirées avant la mise à jour de la barre de vie d'origine ; les boss vivants et les barres d'origine restent inchangés. Correctif défensif en attendant une correction de Fatshark.",
        de = "Verhindert einen Absturz der Boss-Lebensleiste, der vor allem als Client ohne Host-Rolle auftreten kann, wenn mehrere Bosse kurz nacheinander sterben oder verschwinden. Veraltete Boss-Einträge werden vor der Aktualisierung der originalen Boss-Lebensleiste entfernt; lebende Bosse und die originalen Leisten bleiben unverändert. Defensiver Workaround, bis Fatshark das Problem behebt.",
        it = "Impedisce un arresto anomalo della barra della salute dei boss che può verificarsi, soprattutto come client non host, quando più boss muoiono o scompaiono in rapida successione. Le voci dei boss non più valide vengono rimosse prima dell'aggiornamento della barra originale; i boss vivi e le barre originali restano invariati. Soluzione difensiva in attesa di una correzione da parte di Fatshark.",
        es = "Evita un cierre inesperado de la barra de vida de los jefes que puede ocurrir, sobre todo como cliente que no es anfitrión, cuando varios jefes mueren o desaparecen en poco tiempo. Las entradas de jefes obsoletas se eliminan antes de que se actualice la barra de vida original; los jefes vivos y las barras originales no cambian. Solución defensiva hasta que Fatshark corrija el problema.",
        pl = "Zapobiega awarii paska zdrowia bossów, która może wystąpić, głównie jako klient niebędący hostem, gdy kilku bossów ginie lub znika w krótkim odstępie czasu. Nieaktualne wpisy bossów są usuwane przed aktualizacją oryginalnego paska zdrowia; żywi bossowie i oryginalne paski pozostają bez zmian. Obejście ochronne do czasu naprawy problemu przez Fatshark.",
        ["pt-br"] = "Evita um travamento da barra de vida dos chefes que pode ocorrer, principalmente como cliente que não é o anfitrião, quando vários chefes morrem ou desaparecem em sequência rápida. Entradas de chefes obsoletas são removidas antes da atualização da barra de vida original; chefes vivos e as barras originais não são alterados. Solução defensiva até que a Fatshark corrija o problema.",
        ru = "Предотвращает вылет полосы здоровья боссов, который может произойти, в основном у клиента без роли хоста, когда несколько боссов погибают или исчезают в быстрой последовательности. Устаревшие записи боссов удаляются перед обновлением оригинальной полосы здоровья; живые боссы и оригинальные полосы не изменяются. Защитное временное решение, пока Fatshark не исправит проблему.",
        ja = "複数のボスが短時間に倒れたり消えたりした際に、主にホスト以外のクライアントで発生し得るボス体力バーのクラッシュを防ぎます。オリジナルのボス体力バーが更新される前に、無効になったボスの項目を取り除きます。生存中のボスとオリジナルのバーは変わりません。Fatsharkが問題を修正するまでの防御的な回避策です。",
        ko = "여러 보스가 짧은 시간 안에 죽거나 사라질 때, 주로 호스트가 아닌 클라이언트에서 발생할 수 있는 보스 체력 바 충돌을 방지합니다. 원래 보스 체력 바가 갱신되기 전에 더 이상 유효하지 않은 보스 항목을 제거하며, 살아 있는 보스와 원래 체력 바는 그대로 유지됩니다. Fatshark가 문제를 수정할 때까지 사용하는 방어적인 임시 해결책입니다.",
        ["zh-cn"] = "防止首领生命条在多个首领于短时间内死亡或消失时发生崩溃（主要发生在非主机客户端）。在原版首领生命条更新之前移除已失效的首领条目；存活的首领和原版生命条保持不变。这是在 Fatshark 修复该问题之前的防御性临时方案。",
        ["zh-tw"] = "防止首領生命條在多個首領於短時間內死亡或消失時發生崩潰（主要發生在非主機用戶端）。在原版首領生命條更新之前移除已失效的首領條目；存活的首領和原版生命條保持不變。這是在 Fatshark 修正該問題之前的防禦性暫時方案。",
    },
}
