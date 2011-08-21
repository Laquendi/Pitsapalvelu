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
    response.set_cookie("kori", {:value=>'', :path=>'/'})
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
      tuote = $db.get_first_row("select t.nimi, t.id, tt.id as lista_id, tt.lisukkeet from tuote t, tuotetyyppi tt where tt.id=t.tuotetyyppi_id and t.id=?;", idt[0])
      hinta = $db.get_first_row("select saatavilla, hinta, lista from tuote_hinnat where tuote=? and alku<? and loppu>? limit 1;", idt[0], aika, aika)
      if !tuote or !hinta or !hinta['saatavilla']
        next
      end
      lopullinen_sisalto << idt.shift.to_s
      tuote_hash = {:indeksi=>indeksi, :id=>tuote['id'].to_i, :lista=>hinta['lista'], :nimi=>tuote['nimi'], :hinta=>hinta['hinta'], :onko_lisukkeet=>tuote['lisukkeet']}
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
    @summa = @sisalto.reduce(0.0) {|memo, obj| memo+obj[:hinta]}
    haml :kori
  end
  get '/kori/tyhjennys' do
    tyhjenna_kori
    redirect "/kori"
  end
  get '/kori/poista/:tuote_indeksi' do
    sisalto = tarkista_kori
    sisalto.delete_at(params[:tuote_indeksi].to_i)
    keksi = ""
    sisalto.each { |i|
      keksi << i[:id].to_s
      i[:lisukkeet].each { |p|
        keksi << "a#{p}"
      }
      keksi << "b"
    }
    response.set_cookie("kori", {:value=>keksi, :path=>'/'})
    redirect '/kori'
  end
  get '/tilaa' do
    aika = Time.now+(60*35)
    @aika = "#{aika.hour.to_s.rjust(2,'0')}:#{aika.min.to_s.rjust(2,'0')}"
    @sisalto = tarkista_kori
    @summa = @sisalto.reduce(0.0) {|memo, obj| memo+obj[:hinta]}
    @lisukkeet = {}
    $db.execute("select * from lisuke").each { |i|
      @lisukkeet[i['id']]=i['nimi']
	}	
    haml :tilaa
  end
  get '/seuranta' do
    tilaus_id = session[:tilaus]
    tilaus_id ||= -1
    @tilaus = $db.get_first_row("select id, tila, nimi, osoite, toimitusaika from tilaus where id=?;", tilaus_id)
    unless @tilaus
      return haml :ei_seurattavaa
    end
    @tila = $db.get_first_row("select * from tilat where id=?;", @tilaus['tila'])
    @tuotteet = $db.execute("select * from ostos where tilaus_id=?;", tilaus_id)
    @summa = $db.get_first_value("select sum(hinta) from ostos where tilaus_id=?;", tilaus_id)
    @tuote_idt = {}
    $db.execute("select * from tuote;").each { |tuote|
      @tuote_idt[tuote['id']]=tuote['nimi']
    }
    aika = Time.now.to_a
    @tilaus['toimitusaika'] =~ /(\d\d):(\d\d)/
    aika[2]-=$1.to_i
    aika[1]-=$2.to_i
    @erotus = -60*aika[2]-aika[1]
    @tila = $db.get_first_row("select * from tilat where id=?;", @tilaus['tila'])
    haml :seuranta
  end
  get '/peru' do
      tilaus_id = session[:tilaus]
      tilaus_id ||= -1
      @tilaus = $db.get_first_row("select toimitusaika from tilaus where id=?;", tilaus_id)
      if !@tilaus
        return haml :peru
      end
      aika = Time.now.to_a
      @tilaus['toimitusaika'] =~ /(\d\d):(\d\d)/
      aika[2]-=$1.to_i
      aika[1]-=$2.to_i
      @erotus = -60*aika[2]-aika[1]
      if @erotus < 30
        return haml :peru
      end
        $db.execute("update tilaus set tila=? where id=?;", 2, tilaus_id)
      haml :peru
  end

  post '/kori/lisaa_lisuke/:tuote_indeksi' do
      sisalto = tarkista_kori

      lisuke = $db.get_first_value("select id from lisuke where nimi=?",params[:lisuke])
      unless lisuke.nil?
          sisalto[params[:tuote_indeksi].to_i][:lisukkeet].push(lisuke)
          keksi = ""
          sisalto.each { |i|
              keksi << i[:id].to_s
              i[:lisukkeet].each { |p|
                  keksi << "a#{p}"
              }
              keksi << "b"
          }
          response.set_cookie("kori", {:value=>keksi, :path=>'/'})
      end
      redirect '/kori'
  end
  post '/tilaa' do
      sisalto = tarkista_kori
      if sisalto.empty?
          @virhe = "Kori on tyhja"
          return haml :tilaus_epaonnistui
      end
      if params[:toimitus] == '0'
          kotiinkuljetus = 0
      elsif params[:toimitus] == '1'
          kotiinkuljetus = 1
      else
          @virhe = "Valitse joko nouto tai kotiinkuljetus"
          return haml :tilaus_epaonnistui
      end
      if params[:tilaaja_nimi].match(/\A[\w\s]+\Z/)
          tilaaja_nimi = params[:tilaaja_nimi]
      else
          @virhe = "Anna oikea nimi"
          return haml :tilaus_epaonnistui
      end
      if (kotiinkuljetus and params[:tilaaja_osoite].match(/\A[\w\s]+\Z/)) or params[:tilaaja_osoite].match(/\A[\w\s]*\Z/)
          tilaaja_osoite = params[:tilaaja_osoite]
      else
          @virhe = "Kotiinkuljetuksessa taytyy antaa osoite"
          return haml :tilaus_epaonnistui
      end
      if params[:tilaaja_puhelin].match(/\A[+\d\s]{6,}\Z/)
          tilaaja_puhelin = params[:tilaaja_puhelin]
      else
          @virhe = "Anna oikea puhelinnumero"
          return haml :tilaus_epaonnistui
      end
    if params[:toimitusaika].match(/\A(\d\d):(\d\d)\Z/) 
      aika = Time.now.to_a
      aika[2]-=$1.to_i
      aika[1]-=$2.to_i
      erotus = -60*aika[2]-aika[1]
      if erotus >= 30
        toimitusaika = params[:toimitusaika]
      else
        @virhe = "Toimitus aikaisintaan 30min paasta"
        return haml :tilaus_epaonnistui
      end
    else
      @virhe = "Aika muodossa xx:xx. Toimitus aikaisintaan 30min paasta"
      return haml :tilaus_epaonnistui
    end
    lisatiedot = params[:lisatiedot]
    $db.execute("insert into tilaus(kotiinkuljetus,nimi,osoite,puhelin,toimitusaika,lisatiedot,tila,tilausaika) values(?,?,?,?,?,?,?,strftime('%s','now'));",
              kotiinkuljetus, tilaaja_nimi, tilaaja_osoite, tilaaja_puhelin, toimitusaika, lisatiedot, 1);
    id = $db.last_insert_row_id()
    sisalto.each { |tuote|
      $db.execute("insert into ostos(tilaus_id, tuote_id, ruokalista_id, hinta) values(?,?,?,?);", id, tuote[:id], tuote[:lista], tuote[:hinta])
      tuote_id = $db.last_insert_row_id()
      tuote[:lisukkeet].each { |lisuke|
        $db.execute("insert into lisuke_ostos(lisuke_id, ostos_id) values(?,?);", lisuke, tuote_id)
      }
    }
    session[:tilaus]=id
    tyhjenna_kori
    redirect '/seuranta'
  end
end
