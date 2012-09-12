# User Agent

When asking a server for a feed, Mouffette is extremely polite. The request is done with If-None-Match Etag and If-Modified-Since conditional gets. Gzipped response is supported. Most of the times a cheap 304 response is enough.

It also declares itself as: 

`Mozilla (Mouffette RSS->XMPP gateway v.0.X)`

If you are visiting this page because you saw this string in your logs, keep in mind that your feeds are propagated to potentially many clients.


