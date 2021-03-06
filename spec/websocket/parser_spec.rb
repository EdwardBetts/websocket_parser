require 'spec_helper'

describe WebSocket::Parser do
  let(:received_messages) { [] }
  let(:received_errors)   { [] }
  let(:received_closes)   { [] }
  let(:received_pings)    { [] }
  let(:received_pongs)    { [] }

  let(:parser) do
    parser = WebSocket::Parser.new

    parser.on_message { |m| received_messages << m }
    parser.on_error   { |m| received_errors << m }
    parser.on_close   { |status, message| received_closes << [status, message] }
    parser.on_ping    { |m| received_pings << m }
    parser.on_pong    { |m| received_pongs << m }

    parser
  end

  it "recognizes a text message" do
    parser << WebSocket::Message.new('Once upon a time').to_data

    expect(received_messages.first).to eq('Once upon a time')
  end

  it "returns parsed messages on parse" do
    msg1 = WebSocket::Message.new('Now is the winter of our discontent').to_data
    msg2 = WebSocket::Message.new('Made glorious summer by this sun of York').to_data

    messages = parser << msg1.slice!(0,5)
    expect(messages).to be_empty # We don't have a complete message yet

    messages = parser << msg1 + msg2

    expect(messages[0]).to eq('Now is the winter of our discontent')
    expect(messages[1]).to eq('Made glorious summer by this sun of York')
  end

  it "does not return control frames" do
    msg = WebSocket::Message.close(1001, 'Goodbye!').to_data

    messages = parser << msg
    expect(messages).to be_empty
  end

  it "can receive a message in parts" do
    data = WebSocket::Message.new('Once upon a time').to_data
    parser << data.slice!(0, 5)

    expect(received_messages).to be_empty

    parser << data

    expect(received_messages.first).to eq('Once upon a time')
  end

  it "can receive succesive messages" do
    msg1 = WebSocket::Message.new('Now is the winter of our discontent')
    msg2 = WebSocket::Message.new('Made glorious summer by this sun of York')

    parser << msg1.to_data
    parser << msg2.to_data

    expect(received_messages[0]).to eq('Now is the winter of our discontent')
    expect(received_messages[1]).to eq('Made glorious summer by this sun of York')
  end

  it "can receive medium size messages" do
    # Medium size messages has a payload length between 127 and 65_535 bytes

    text = 4.times.collect { 'All work and no play makes Jack a dull boy.' }.join("\n\n")
    expect(text.length).to be > 127
    expect(text.length).to be < 65_536

    parser << WebSocket::Message.new(text).to_data
    expect(received_messages.first).to eq(text)
  end

  it "can receive large size messages" do
    # Large size messages has a payload length greater than 65_535 bytes

    text = 1500.times.collect { 'All work and no play makes Jack a dull boy.' }.join("\n\n")
    expect(text.length).to be > 65_536

    parser << WebSocket::Message.new(text).to_data

    # Check lengths first to avoid gigantic error message
    expect(received_messages.first.length).to eq(text.length)
    expect(received_messages.first).to eq(text)
  end

  it "recognizes a ping message" do
    parser << WebSocket::Message.ping.to_data

    expect(received_pings.size).to eq(1)
  end

  it "recognizes a pong message" do
    parser << WebSocket::Message.pong.to_data

    expect(received_pongs.size).to eq(1)
  end

  it "recognizes a close message with status code and message" do
    parser << WebSocket::Message.close(1001, 'Browser leaving page').to_data

    status, message = received_closes.first
    expect(status).to  eq(:peer_going_away) # Status code 1001
    expect(message).to eq('Browser leaving page')
  end

  it "recognizes a close message without status code" do
    parser << WebSocket::Message.close.to_data

    status, message = received_closes.first
    expect(status).to  be_nil
    expect(message).to be_empty
  end

  it "recognizes a masked frame" do
    msg = WebSocket::Message.new('Once upon a time')
    msg.mask!

    parser << msg.to_data

    expect(received_messages.first).to eq('Once upon a time')
  end

  context "examples from the spec" do
    # These are literal examples from the spec

    it "recognizes single-frame unmasked text message" do
      parser << [0x81, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f].pack('C*')

      expect(received_messages.first).to eq('Hello')
    end

    it "recognizes single-frame masked text message" do
      parser << [0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58].pack('C*')

      expect(received_messages.first).to eq('Hello')
    end

    it "recognizes a fragmented unmasked text message" do
      parser << [0x01, 0x03, 0x48, 0x65, 0x6c].pack('C*') # contains "Hel"

      expect(received_messages).to be_empty

      parser << [0x80, 0x02, 0x6c, 0x6f].pack('C*') # contains "lo"

      expect(received_messages.first).to eq('Hello')
    end

    it "recognizes an unnmasked ping request" do
      parser << [0x89, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f].pack('C*')

      expect(received_pings.size).to eq(1)
    end

    it "recognizes a masked pong response" do
      parser << [0x8a, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58].pack('C*')

      expect(received_pongs.size).to eq(1)
    end

    it "recognizes 256 bytes binary message in a single unmasked frame" do
      data = Array.new(256) { rand(256) }.pack('c*')
      parser << [0x82, 0x7E, 0x0100].pack('CCn') + data

      expect(received_messages.first).to eq(data)
    end

    it "recoginzes 64KiB binary message in a single unmasked frame" do
      data = Array.new(65536) { rand(256) }.pack('c*')
      parser << [0x82, 0x7F, 0x0000000000010000].pack('CCQ>') + data

      expect(received_messages.first).to eq(data)
    end
  end
end
