mouffette
=========

Mouffette is an RSS->XMPP/Jabber gateway. It let you to receive the RSS/Atom feeds in your Jabber client or application.

## Usage

If you just want to read the RSS/Atom feeds in your XMPP/Jabber client, without installing anything, you are free to add mouffette@laltromondo.dynalias.net to your roster, and add your feed sending to the bot a message with  `feed mouffette https://github.com/melmothx/mouffette/commits/master.atom` or `help`. This account is always running the latest and the greatest. You can add as many feed you want.

## Installation

Mouffette is written in Perl and AnyEvent. This is the list of the required modules to be installed from the cpan or, on a Debian box starting from wheezy (squeeze has unavailable or outdated modules)

 * AnyEvent (libanyevent-perl)
 * AnyEvent::XMPP (libanyevent-xmpp-perl)
 * AnyEvent::HTTP (libanyevent-http-perl)
 * AnyEvent::HTTPD (libanyevent-httpd-perl)
 * EV (optional, for better performance) (libev-perl)
 * XML::TreePP (libxml-treepp-perl)
 * XML::FeedPP (libxml-feedpp-perl)
 * Try::Tiny   (libtry-tiny-perl)
 * Date::Parse (libtimedate-perl)
 * HTML::Parser (libhtml-parser-perl)
 * YAML::Any    (libyaml-perl)

Once you have the dependencies installed, create a XMPP account to run the bot, edit the example configuration file (in YAML format) to match the credentials, set the interval to something reasonable (recommended value is 500-600 seconds), and run it. Then see "Usage above".




