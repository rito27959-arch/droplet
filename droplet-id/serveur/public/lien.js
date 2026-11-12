// Test environment only: carry the request id from /a/<id> to the test device.
(() => {
  const a = document.querySelector('[data-vers-test]');
  const id = location.pathname.split('/').pop();
  if (a && id) a.href = `/test/appareil#${id}`;
})();
