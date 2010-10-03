require "rubygems"
require "nokogiri"
require "mongo"
require "pp"
require "chronic"
require "active_support"
require "tumblr"

$username = ""
$password = ""
$root = "/Users/tom/blog" # where your opml files are stored

# set LOCATION_STORE to true if you want to store data in a local mongo instance
LOCATION_STORE = true

def location_callback(hash)
  if LOCATION_STORE == true
    # store date and location in Mongo
    db = Mongo::Connection.new.db("locations")
    collection = db.collection("locations")
    collection.insert(hash)
  else
    true
  end
end

`find #{$root} | grep -i opml | grep -v swp`.split.each {|file|

puts "[info] now doing #{file}"
Nokogiri::XML(open(file)).xpath("//body/outline").map {|entry|

  # this may need some date parsing code later
  if entry.attributes.member?("created")
    date = Time.parse(entry.attributes["created"].to_s)
  else
    date = DateTime.strptime(file, "#{$root}/%Y/%m/%d.opml").to_time
  end

  if entry.search("outline").size == 0
    # for single paragraph entries
    body = "<p>" + entry.attributes["text"].to_s + "</p>\n"
  else
    # for titled, long entries
    title = entry.attributes["text"].to_s
    body = ""
    entry.search("outline").each {|crow|
      body += "<p>" + crow.attributes["text"].to_s + "</p>\n"
      if crow.search("outline").size != 0
        # in OPML blogging, a blockquote is a child of the element before it.
        body += "<blockquote>\n"
        crow.search("outline").each {|bq|
          body += "<p>" + bq.attributes["text"].to_s + "</p>\n"
        }
        body += "</blockquote>\n"
      end
    }
  end

  # detect whether we have a geo location
  geo = {}
  if entry.attribute_with_ns("lat", "http://www.w3.org/2003/01/geo/wgs84_pos#")
    geo[:lat] = entry.attribute_with_ns("lat", "http://www.w3.org/2003/01/geo/wgs84_pos#").text
  end
  if entry.attribute_with_ns("long", "http://www.w3.org/2003/01/geo/wgs84_pos#")
    geo[:long] = entry.attribute_with_ns("long", "http://www.w3.org/2003/01/geo/wgs84_pos#").text
  end
  if entry.attribute_with_ns("location", "http://tommorris.org/ns/fireeagle/")
    geo[:label] = entry.attribute_with_ns("location", "http://tommorris.org/ns/fireeagle/").text
  end
  # location_callback is to store location info into a local DB (by default MongoDB)
  if geo != {}
    location_callback({:date => date, :geo => geo})
    body += "<p class=\"location fireeagle\"><abbr class=\"geo\" title=\"#{geo[:lat]};#{geo[:long]}\">#{geo[:label]}</p>\n"
  end

  # <p class="location fireeagle"><abbr class="geo" title="#{latitude};#{longitude}">#{title}</abbr></p>

  {:date => date, :body => body, :title => title, :geo => geo}
}.map {|hash|
  output = "---\ntype: regular\nstate: published\nformat: html\n"
  if hash[:date] && hash[:date] != nil
    output += "date: #{hash[:date].strftime('%Y-%m-%dT%H:%M:%S%z')}"
  end
  output += "\nsend-to-twitter: no\n"
  if hash[:title] && hash[:title] != nil && hash[:title] != ""
    output += "title: \"#{hash[:title]}\"\n"
  end
  output += "tags: imported\n"
  output += "---\n"
  output += hash[:body]
  output
}.each {|entry|
  request = Tumblr.new($username, $password).post(entry)
  request.perform do |response|
    if response.success?
      puts response.body
    else
      puts "Something went wrong: #{response.code} #{response.message}"
    end
  end
}

}
