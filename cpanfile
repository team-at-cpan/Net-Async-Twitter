requires 'parent', 0;
requires 'curry', 0;
requires 'Future', '>= 0.15';
requires 'Mixin::Event::Dispatch', '>= 1.000';
requires 'MIME::Base64', 0;
requires 'URI::Escape', 0;
requires 'Digest::HMAC', 0;
requires 'Digest::SHA1', 0;
requires 'List::UtilsBy', 0;

on 'test' => sub {
	requires 'Test::More', '>= 0.98';
	requires 'Test::Fatal', '>= 0.010';
};

