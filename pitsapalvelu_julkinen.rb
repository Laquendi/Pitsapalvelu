require 'rubygems'
require 'sinatra/base'
require 'haml'
require 'sqlite3'

class Pitsapalvelu_julkinen < Sinatra::Base
  set :sessions, true
  set :static, true
  set :public, 'public'

  $db = SQLite3::Database.new("database.db")
  $db.type_translation = true
  $db.results_as_hash = true

  def tyhjenna_kori
    response.set_cookie("kori", {:value=>'', :path=>'/',})
  end

  def tarkista_kori
    aika = "#{Time.now.hour.to_s.rjust(2,'0')}:#{Time.now.min.to_s.rjust(2,'0')}"
    keksi = request.cookies["kori"]
    keksi ||=""
    if !keksi.match(/\A((a?\d+)+b)*\Z/)
      tyhjenna_kori
      return []
    end
    sisalto = keksi.split('b')
    lopullinen_sisalto = ""
    tuotteet = []
    indeksi = 0
    sisalto.each { |i|
      idt = i.split('a')
      tuote = $db.get_first_row("select t.nimi, t.id, tt.lisukkeet from tuote t, tuotetyyppi tt where tt.id=t.tuotetyyppi_id and t.id=?;", idt[0])
      hinta = $db.get_first_row("select saatavilla, hinta from tuote_hinnat where tuote=? and alku<? and loppu>? limit 1;", idt[0], aika, aika)
      if !tuote or !hinta or !hinta['saatavilla']
        next
      end
      lopullinen_sisalto << idt.shift.to_s
      tuote_hash = {:indeksi=>indeksi, :id=>tuote['id'].to_i, :nimi=>tuote['nimi'], :hinta=>hinta['hinta'], :onko_lisukkeet=>tuote['lisukkeet']}
      tuote_lisukkeet=[]
      if tuote['lisukkeet']
        idt.each{ |lisuke_id|
          if $db.execute("select * from lisuke where id=?",lisuke_id)
            lopullinen_sisalto << "a#{lisuke_id}"
            tuote_lisukkeet << lisuke_id.to_i
          end
        }
      end
      tuote_hash[:lisukkeet] = tuote_lisukkeet
      lopullinen_sisalto << 'b'
      indeksi+=1
      tuote_hash[:retard]=keksi
      tuotteet.push(tuote_hash)
    }
    response.set_cookie("kori", {:value=>lopullinen_sisalto, :path=>'/'})
    return tuotteet
  end

  get '/' do
    haml :index
  end
  get '/yhteystiedot' do
    haml :yhteystiedot
  end
  get '/hinnasto' do
    aika = "#{Time.now.hour.to_s.rjust(2,'0')}:#{Time.now.min.to_s.rjust(2,'0')}"
    @lista = $db.get_first_row("select * from ruokalista where alku<? and loppu>? order by prioriteetti desc limit 1;", aika, aika)
    if !@lista
        haml :hinnasto_suljettu
    else
      @tuotetyypit = $db.execute("select * from tuotetyyppi;")
	  @tuotetyypit.each do |tuotetyyppi|
        tuotetyyppi['tuotteet'] = $db.execute("select * from tuote where tuotetyyppi_id = ?;", tuotetyyppi['id'])
        tuotetyyppi['tuotteet'].each do |tuote|
          hinta = $db.get_first_row("select saatavilla, hinta from tuote_hinnat where tuote=? and alku<? and loppu>? limit 1;", tuote['id'], aika, aika)
          if !hinta or !hinta['saatavilla']
            tuotetyyppi.delete(tuote)
	          next
            end
            tuote['hinta']=hinta['hinta']
          end
        end
      haml :hinnasto
    end
  end
  get '/muutlistat/:lista' do
    @listat = $db.execute("select * from ruokalista;")
    @lista = $db.get_first_row("select * from ruokalista where id=?", params[:lista])
    @tuotteet = $db.execute("select * from lista_jasen, tuote where id=tuote_id and ruokalista_id=?", params[:lista])
    haml :muutlistat
  end
  get '/muutlistat' do
    lista = $db.get_first_value("select id from ruokalista where nimi=?;", params[:lista])
    redirect "/muutlistat/#{lista}"
  end
  get '/kori' do
    @sisalto = tarkista_kori
    @lisukkeet = {}
    $db.execute("select * from lisuke").each { |i|
      @lisukkeet[i['id']]=i['nimi']
    }
    haml :kori
  end
  get '/kori/tyhjennys' do
    tyhjenna_kori
    redirect "/kori"
  end
  post '/kori/lisaa_lisuke/:tuote_indeksi' do
    @sisalto = tarkista_kori

    lisuke = $db.get_first_value("select id from lisuke where nimi=?",params[:lisuke])
    unless lisuke.nil?
      @sisalto[params[:tuote_indeksi].to_i][:lisukkeet].push(lisuke)
      keksi = ""
      @sisalto.each { |i|
        keksi << i[:id].to_s
        i[:lisukkeet].each { |p|
          keksi << "a#{p}"
        }
        keksi << "b"
      }
      response.set_cookie("kori", {:value=>keksi, :path=>'/'})
    end
    @lisukkeet = {}
    $db.execute("select * from lisuke").each { |i|
      @lisukkeet[i['id']]=i['nimi']
    }
    haml :kori
  end
end
