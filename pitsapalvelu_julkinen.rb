require 'rubygems'
require 'sinatra/base'
require 'haml'
require 'sqlite3'

class Pitsapalvelu_julkinen < Sinatra::Base
  set :sessions, true
  set :static, true
  set :public, 'public'

  db = SQLite3::Database.new("database.db")
  db.type_translation = true
  db.results_as_hash = true

  get '/' do
    haml :index
  end
  get '/yhteystiedot' do
    haml :yhteystiedot
  end
  get '/hinnasto' do
    aika = "#{Time.now.hour}:#{Time.now.min}"
    @lista = db.get_first_row("select * from ruokalista where alku<? and loppu>? order by prioriteetti desc limit 1;", aika, aika)
    @tuotetyypit = db.execute("select * from tuotetyyppi;")
	@tuotetyypit.each do |tuotetyyppi|
      tuotetyyppi['tuotteet'] = db.execute("select * from tuote where tuotetyyppi_id = ?;", tuotetyyppi['id'])
      tuotetyyppi['tuotteet'].each do |tuote|
        hinta = db.get_first_row("select saatavilla, hinta from tuote_hinnat where tuote=? and alku<? and loppu>? limit 1;", tuote['id'], aika, aika)
        if !hinta && !hinta['saatavilla']
          tuotetyyppi.delete(tuote)
        end
        tuote['hinta']=hinta['hinta']
      end
    end
    haml :hinnasto
  end
  get '/muutlistat/:lista' do
    @listat = db.execute("select * from ruokalista;")
    @lista = db.get_first_row("select * from ruokalista where id=?", params[:lista])
    @tuotteet = db.execute("select * from lista_jasen, tuote where id=tuote_id and ruokalista_id=?", params[:lista])
    haml :muutlistat
  end
  get '/muutlistat' do
    lista = db.get_first_value("select id from ruokalista where nimi=?;", params[:lista])
    redirect "/muutlistat/#{lista}"
  end
  get '/kori' do
    keksi = cookie = request.cookies["kori"]
    keksi ||=""
    @sisalto = keksi.split(' ').map{|i| i.to_i}
    @tuotteet = {}
    tuotteet = db.execute("select * from tuote;")
    tuotteet.each do |tuote|
      @tuotteet[tuote['id']]=tuote
    end
    haml :kori
  end
end
