// "Continue to…": the username field follows its switch.
(() => {
  const bascule = document.querySelector('[data-bascule-pseudo]');
  const champ = document.querySelector('[data-champ-pseudo]');
  if (!bascule || !champ) return;
  const maj = () => champ.classList.toggle('cache', !bascule.checked);
  bascule.addEventListener('change', maj);
  maj();
})();
