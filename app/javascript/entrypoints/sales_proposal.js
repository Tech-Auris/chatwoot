// The public proposal page is rendered by Rails and only needs its stylesheet.
// It goes through a JavaScript entrypoint because that is the name Vite writes
// to the manifest — a `.scss` entrypoint is filed under its own extension and
// `vite_stylesheet_tag` looks for `.css`, which is a mismatch that only shows
// up on built assets. Same shape as the super admin console.
import '../sales_proposal/application.scss';
