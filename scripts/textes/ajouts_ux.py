# Les textes ajoutés avec le glisser-déposer, le radar et les Réglages
# groupés (les dix langues, mêmes clés).
AJOUTS = {
 'fr': {'aujourd_hui': "Aujourd’hui", 'hier': "Hier", 'deposer_titre': "Déposez pour envoyer", 'deposer_texte': "Vous choisirez ensuite à qui.", 'recherche_appareils': "Recherche des appareils autour de vous…", 'general': "Général"},
 'en': {'aujourd_hui': "Today", 'hier': "Yesterday", 'deposer_titre': "Drop to send", 'deposer_texte': "You’ll choose who gets them next.", 'recherche_appareils': "Looking for devices around you…", 'general': "General"},
 'es': {'aujourd_hui': "Hoy", 'hier': "Ayer", 'deposer_titre': "Suelta para enviar", 'deposer_texte': "Después eliges a quién.", 'recherche_appareils': "Buscando dispositivos a tu alrededor…", 'general': "General"},
 'de': {'aujourd_hui': "Heute", 'hier': "Gestern", 'deposer_titre': "Zum Senden ablegen", 'deposer_texte': "Danach wählst du die Empfänger.", 'recherche_appareils': "Suche nach Geräten in deiner Nähe …", 'general': "Allgemein"},
 'it': {'aujourd_hui': "Oggi", 'hier': "Ieri", 'deposer_titre': "Rilascia per inviare", 'deposer_texte': "Poi sceglierai a chi.", 'recherche_appareils': "Ricerca dei dispositivi intorno a te…", 'general': "Generali"},
 'pt': {'aujourd_hui': "Hoje", 'hier': "Ontem", 'deposer_titre': "Largue para enviar", 'deposer_texte': "Depois escolhe para quem.", 'recherche_appareils': "A procurar dispositivos à sua volta…", 'general': "Geral"},
 'ru': {'aujourd_hui': "Сегодня", 'hier': "Вчера", 'deposer_titre': "Отпустите, чтобы отправить", 'deposer_texte': "Затем выберете, кому.", 'recherche_appareils': "Поиск устройств рядом…", 'general': "Основные"},
 'ar': {'aujourd_hui': "اليوم", 'hier': "أمس", 'deposer_titre': "أفلِت للإرسال", 'deposer_texte': "ستختار المستلمين بعد ذلك.", 'recherche_appareils': "جارٍ البحث عن الأجهزة من حولك…", 'general': "عام"},
 'hi': {'aujourd_hui': "आज", 'hier': "कल", 'deposer_titre': "भेजने के लिए छोड़ें", 'deposer_texte': "फिर चुनें कि किसे भेजना है।", 'recherche_appareils': "आस-पास के डिवाइस खोजे जा रहे हैं…", 'general': "सामान्य"},
 'zh': {'aujourd_hui': "今天", 'hier': "昨天", 'deposer_titre': "松开即可发送", 'deposer_texte': "接下来选择接收方。", 'recherche_appareils': "正在搜索身边的设备…", 'general': "通用"},
}

# Windows : autoriser la réception à travers le pare-feu.
PARE_FEU = {
 'fr': {'pare_feu_titre': "Autoriser la réception", 'pare_feu_texte': "Le pare-feu de Windows peut empêcher les autres appareils de vous joindre. Autorisez Droplet Drop une fois pour toutes ; Windows vous demandera de confirmer.", 'pare_feu_bouton': "Autoriser", 'pare_feu_ok': "Réception autorisée.", 'pare_feu_echec': "Windows n’a pas autorisé la réception."},
 'en': {'pare_feu_titre': "Allow receiving", 'pare_feu_texte': "Windows Firewall can stop other devices from reaching you. Allow Droplet Drop once and for all; Windows will ask you to confirm.", 'pare_feu_bouton': "Allow", 'pare_feu_ok': "Receiving is allowed.", 'pare_feu_echec': "Windows didn’t allow receiving."},
 'es': {'pare_feu_titre': "Permitir la recepción", 'pare_feu_texte': "El firewall de Windows puede impedir que otros dispositivos te alcancen. Permite Droplet Drop de una vez por todas; Windows te pedirá que lo confirmes.", 'pare_feu_bouton': "Permitir", 'pare_feu_ok': "Recepción permitida.", 'pare_feu_echec': "Windows no ha permitido la recepción."},
 'de': {'pare_feu_titre': "Empfang erlauben", 'pare_feu_texte': "Die Windows-Firewall kann verhindern, dass andere Geräte dich erreichen. Erlaube Droplet Drop ein für alle Mal; Windows bittet dich um Bestätigung.", 'pare_feu_bouton': "Erlauben", 'pare_feu_ok': "Empfang ist erlaubt.", 'pare_feu_echec': "Windows hat den Empfang nicht erlaubt."},
 'it': {'pare_feu_titre': "Consenti la ricezione", 'pare_feu_texte': "Il firewall di Windows può impedire agli altri dispositivi di raggiungerti. Consenti Droplet Drop una volta per tutte; Windows ti chiederà di confermare.", 'pare_feu_bouton': "Consenti", 'pare_feu_ok': "Ricezione consentita.", 'pare_feu_echec': "Windows non ha consentito la ricezione."},
 'pt': {'pare_feu_titre': "Permitir a receção", 'pare_feu_texte': "A firewall do Windows pode impedir que outros dispositivos o alcancem. Permita o Droplet Drop de uma vez por todas; o Windows vai pedir-lhe que confirme.", 'pare_feu_bouton': "Permitir", 'pare_feu_ok': "Receção permitida.", 'pare_feu_echec': "O Windows não permitiu a receção."},
 'ru': {'pare_feu_titre': "Разрешить приём", 'pare_feu_texte': "Брандмауэр Windows может не пускать к вам другие устройства. Разрешите Droplet Drop один раз — Windows попросит подтвердить.", 'pare_feu_bouton': "Разрешить", 'pare_feu_ok': "Приём разрешён.", 'pare_feu_echec': "Windows не разрешила приём."},
 'ar': {'pare_feu_titre': "السماح بالاستلام", 'pare_feu_texte': "قد يمنع جدار حماية Windows الأجهزة الأخرى من الوصول إليك. اسمح لـ Droplet Drop مرة واحدة وإلى الأبد؛ سيطلب منك Windows التأكيد.", 'pare_feu_bouton': "السماح", 'pare_feu_ok': "تم السماح بالاستلام.", 'pare_feu_echec': "لم يسمح Windows بالاستلام."},
 'hi': {'pare_feu_titre': "प्राप्त करने की अनुमति दें", 'pare_feu_texte': "Windows फ़ायरवॉल दूसरे डिवाइसों को आप तक पहुँचने से रोक सकता है। Droplet Drop को एक बार अनुमति दें; Windows पुष्टि के लिए पूछेगा।", 'pare_feu_bouton': "अनुमति दें", 'pare_feu_ok': "प्राप्त करने की अनुमति मिल गई।", 'pare_feu_echec': "Windows ने प्राप्त करने की अनुमति नहीं दी।"},
 'zh': {'pare_feu_titre': "允许接收", 'pare_feu_texte': "Windows 防火墙可能会阻止其他设备连接到你。允许 Droplet Drop 一次即可长期生效；Windows 会请你确认。", 'pare_feu_bouton': "允许", 'pare_feu_ok': "已允许接收。", 'pare_feu_echec': "Windows 未允许接收。"},
}
for _l, _d in PARE_FEU.items():
    AJOUTS[_l].update(_d)
