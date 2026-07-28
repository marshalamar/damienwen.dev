import Link from "next/link";

export function SiteHeader() {
  return (
    <header className="site-header">
      <Link className="wordmark" href="/" aria-label="返回首页">
        <span className="wordmark-mark" aria-hidden="true" />
        <strong>Damien Wen</strong>
      </Link>

      <nav aria-label="主导航">
        <a
          href="https://github.com/marshalamar"
          target="_blank"
          rel="noreferrer"
        >
          GitHub ↗
        </a>
      </nav>
    </header>
  );
}
