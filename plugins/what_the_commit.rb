require 'open-uri'
require 'nokogiri'

class WhatTheCommit
  include Cinch::Plugin

  match /commit/
 
  def execute(m)
    open 'http://whatthecommit.com/' do |io|
      m.reply Nokogiri::HTML(io).css('#content > p:first').text.strip
    end
  rescue
    m.reply "I broke this"
  end
end
