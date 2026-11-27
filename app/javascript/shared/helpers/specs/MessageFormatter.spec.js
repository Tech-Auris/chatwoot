import MessageFormatter from '../MessageFormatter';

describe('#MessageFormatter', () => {
  describe('content with links', () => {
    it('should format correctly', () => {
      const message =
        'Chatwoot is an opensource tool. [Chatwoot](https://www.chatwoot.com)';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        '<p>Chatwoot is an opensource tool. <a href="https://www.chatwoot.com" class="link" rel="noreferrer noopener nofollow" target="_blank">Chatwoot</a></p>'
      );
    });
    it('should format correctly', () => {
      const message =
        'Chatwoot is an opensource tool. https://www.chatwoot.com';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        '<p>Chatwoot is an opensource tool. <a href="https://www.chatwoot.com" class="link" rel="noreferrer noopener nofollow" target="_blank">https://www.chatwoot.com</a></p>'
      );
    });
    it('should not convert template variables to links when linkify is disabled', () => {
      const message = 'Hey {{customer.name}}, check https://chatwoot.com';
      const formatter = new MessageFormatter(message, false, false, false);
      expect(formatter.formattedMessage).toMatch(
        '<p>Hey {{customer.name}}, check https://chatwoot.com</p>'
      );
    });
  });

  describe('parses heading to strong', () => {
    it('should format correctly', () => {
      const message = '### opensource \n ## tool';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        `<h3>opensource</h3>
<h2>tool</h2>`
      );
    });

    it('should not render a setext heading when text is followed by "--"', () => {
      const message = 'hy\n\n\\\n\\-\\-\n\nHello there';
      const result = new MessageFormatter(message).formattedMessage;
      expect(result).not.toMatch('<h2>');
      expect(result).not.toMatch('<h1>');
    });
  });

  describe('content with image and has "cw_image_height" query at the end of URL', () => {
    it('should set image height correctly', () => {
      const message =
        'Chatwoot is an opensource tool. ![](http://chatwoot.com/chatwoot.png?cw_image_height=24px)';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        '<p>Chatwoot is an opensource tool. <img src="http://chatwoot.com/chatwoot.png?cw_image_height=24px" alt="" style="height: 24px;" /></p>'
      );
    });

    it('should set image height correctly if its original size', () => {
      const message =
        'Chatwoot is an opensource tool. ![](http://chatwoot.com/chatwoot.png?cw_image_height=auto)';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        '<p>Chatwoot is an opensource tool. <img src="http://chatwoot.com/chatwoot.png?cw_image_height=auto" alt="" style="height: auto;" /></p>'
      );
    });

    it('should not set height', () => {
      const message =
        'Chatwoot is an opensource tool. ![](http://chatwoot.com/chatwoot.png)';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        '<p>Chatwoot is an opensource tool. <img src="http://chatwoot.com/chatwoot.png" alt="" /></p>'
      );
    });
  });

  describe('tweets', () => {
    it('should return the same string if not tags or @mentions', () => {
      const message = 'Chatwoot is an opensource tool';
      expect(new MessageFormatter(message).formattedMessage).toMatch(message);
    });

    it('should add links to @mentions', () => {
      const message =
        '@chatwootapp is an opensource tool thanks @longnonexistenttwitterusername';
      expect(
        new MessageFormatter(message, true, false).formattedMessage
      ).toMatch(
        '<p><a href="http://twitter.com/chatwootapp" class="link" rel="noreferrer noopener nofollow" target="_blank">@chatwootapp</a> is an opensource tool thanks @longnonexistenttwitterusername</p>'
      );
    });

    it('should add links to #tags', () => {
      const message = '#chatwootapp is an opensource tool';
      expect(
        new MessageFormatter(message, true, false).formattedMessage
      ).toMatch(
        '<p><a href="https://twitter.com/hashtag/chatwootapp" class="link" rel="noreferrer noopener nofollow" target="_blank">#chatwootapp</a> is an opensource tool</p>'
      );
    });
  });

  describe('private notes', () => {
    it('should return the same string if not tags or @mentions', () => {
      const message = 'Chatwoot is an opensource tool';
      expect(new MessageFormatter(message).formattedMessage).toMatch(message);
    });

    it('should add links to @mentions', () => {
      const message =
        '@chatwootapp is an opensource tool thanks @longnonexistenttwitterusername';
      expect(
        new MessageFormatter(message, false, true).formattedMessage
      ).toMatch(message);
    });

    it('should add links to #tags', () => {
      const message = '#chatwootapp is an opensource tool';
      expect(
        new MessageFormatter(message, false, true).formattedMessage
      ).toMatch(message);
    });
  });

  describe('plain text content', () => {
    it('returns the plain text without HTML', () => {
      const message =
        '<b>Chatwoot is an opensource tool. https://www.chatwoot.com</b>';
      expect(new MessageFormatter(message).plainText).toMatch(
        'Chatwoot is an opensource tool. https://www.chatwoot.com'
      );
    });
  });

  describe('#sanitize', () => {
    it('sanitizes markup and removes all unnecessary elements', () => {
      const message =
        '[xssLink](javascript:alert(document.cookie))\n[normalLink](https://google.com)**I am a bold text paragraph**';
      expect(new MessageFormatter(message).formattedMessage).toMatch(
        `<p>[xssLink](javascript:alert(document.cookie))<br />
<a href="https://google.com" class="link" rel="noreferrer noopener nofollow" target="_blank">normalLink</a><strong>I am a bold text paragraph</strong></p>`
      );
    });
  });

  describe('conversation mentions', () => {
    it('renders conversation mention with # prefix', () => {
      const message = '[@42](mention://conversation/42/42)';
      const result = new MessageFormatter(message).formattedMessage;
      expect(result).toContain('#42');
      expect(result).toContain('prosemirror-mention-conversation');
      expect(result).not.toContain('@42');
    });

    it('includes data-conversation-id attribute', () => {
      const message = '[@99](mention://conversation/99/99)';
      const result = new MessageFormatter(message).formattedMessage;
      expect(result).toContain('data-conversation-id="99"');
    });

    it('renders both user and conversation mentions in mixed content', () => {
      const message =
        'Hey [@John](mention://user/1/John) check [@42](mention://conversation/42/42)';
      const result = new MessageFormatter(message).formattedMessage;
      expect(result).toContain(
        '<span class="prosemirror-mention-node">@John</span>'
      );
      expect(result).toContain('#42');
      expect(result).toContain('prosemirror-mention-conversation');
    });
  });

  describe('mention label escaping', () => {
    const payload = '<img src=x onerror="alert(1)">';
    const escaped = '&lt;img src=x onerror=&quot;alert(1)&quot;&gt;';

    it('escapes HTML in user mention labels', () => {
      const html = new MessageFormatter(`[${payload}](mention://user/1/x)`)
        .formattedMessage;
      expect(html).not.toContain('<img');
      expect(html).toContain(
        `<span class="prosemirror-mention-node">${escaped}</span>`
      );
    });

    it('escapes HTML in contact mention labels', () => {
      const html = new MessageFormatter(`[${payload}](mention://contact/1/x)`)
        .formattedMessage;
      expect(html).not.toContain('<img');
      expect(html).toContain(
        `<span class="prosemirror-mention-node prosemirror-mention-contact">${escaped}</span>`
      );
    });

    it('escapes HTML in conversation mention labels', () => {
      const html = new MessageFormatter(
        '[@1" onclick="x](mention://conversation/1/1)'
      ).formattedMessage;
      expect(html).not.toContain('onclick="x"');
      expect(html).toContain('data-conversation-id="1&quot; onclick=&quot;x"');
    });
  });
});
