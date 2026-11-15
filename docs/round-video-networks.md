# Kółeczka na kolejnych sieciach

Można wykorzystać istniejące moduły z oryginalnego ChatLoom: wspólny interfejs
nagrywania, przygotowanie pliku, szyfrowaną kolejkę i odtwarzacz. Wysyłka
powinna wybierać format na podstawie możliwości konkretnego mostka i czatu.
Ten dokument jest planem; nie dodaje nowych tras ani nagrywania na iOS.

Obecny `RoundSendRoute` obsługuje Telegram, Messenger (`facebook`) i Instagram.
`PlatformInfos.supportsRoundCapture` udostępnia nagrywanie wyłącznie na Androidzie
i macOS. Odtwarzanie używa wspólnych widgetów, lecz test kontrolera na Windows
nie potwierdza działania kodeka i kamery na iPhonie.

1. **Recorder iOS.** Dodać adapter AVFoundation do istniejącego kontraktu
   `RoundCaptureBackend`, zamiast tworzyć nowy flow nagrywania w Dart. Obsłużyć
   kamerę przednią/tylną, uprawnienia, mikrofon, obrót i podgląd, anulowanie,
   blokadę ekranu oraz przerwania audio. Eksportować kwadratowe H.264/AAC w MP4,
   miniaturę i zweryfikowane parametry przez `RoundMediaPreparer`. Fizycznie
   usunąć obszary poza okręgiem, jeżeli obowiązuje dotychczasowa polityka
   prywatności kółeczek. Nie wystarczy włączyć flagi dostępności na iOS.
2. **Trasa przenośna.** Uogólnić istniejącą trasę Meta na zwykłą wiadomość
   `m.video`, po potwierdzeniu obsługi wideo oraz limitu pliku przez docelowy
   mostek. Dodać WhatsApp, potem kolejne sieci. Lokalny marker ChatLoom pozwala
   wyświetlać własne nagranie w okręgu; mostek wysyła kompatybilny plik MP4.
   Jeśli sieć nie wspiera odpowiedniego formatu, zaoferować zwykłe wideo lub
   wyłączyć nagrywanie z krótkim powodem.
3. **Format natywny, gdy dostępny.** Telegram pozostaje osobnym adapterem:
   natywne video note wymaga deklarowanej obsługi rozszerzenia przez zaufany
   mostek. Dla innych sieci dodawać natywny wariant tylko wtedy, gdy konkretny
   mostek rzeczywiście go obsługuje. Zwykłe MP4 może być u odbiorcy prostokątne;
   klient ChatLoom nie narzuci interfejsu WhatsAppowi czy Messengerowi.
4. **Wspólna niezawodność.** Zachować istniejący outbox, identyfikator próby,
   konto, pokój, mostek i odpowiedź przypięte do rozpoczętego nagrania.
   Ponowienie nie może zmienić odbiorcy ani utworzyć duplikatu. Nie przenosić
   telegramowych potwierdzeń odtworzenia, cichej wysyłki i kontroli przekazywania
   na sieci, które ich nie deklarują.

Przed udostępnieniem sprawdzić na prawdziwym iPhonie oraz po obu stronach
każdego mostka: nagranie i odsłuch, anulowanie, odmowę uprawnień, blokadę i powrót
z tła, zmianę konta/sieci podczas przygotowania, offline i ponowienie, limity
rozmiaru, miniaturę, szyfrowanie i brak niezamierzonych potwierdzeń odczytu.
Najkrótsza droga do użytecznej wersji: recorder iOS, następnie przenośna trasa
MP4 dla WhatsAppa; natywne formaty kolejnych sieci można dodawać stopniowo.
