/* The page scrollbar stays hidden while the page is at the top and shows itself as
   soon as it leaves, per the house rule. The space it occupies is kept either way. */
const root = document.documentElement;
const mark = () => root.classList.toggle("at-top", window.scrollY === 0);
addEventListener("scroll", mark, { passive: true });
addEventListener("resize", mark, { passive: true });
mark();
