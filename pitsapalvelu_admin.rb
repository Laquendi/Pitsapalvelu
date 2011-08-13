require 'rubygems'
require 'sinatra/base'
require 'haml'
require 'sqlite3'

class Pitsapalvelu_admin < Sinatra::Base
  set :sessions, true
  set :static, true
  set :public, 'public'

  db = SQLite3::Database.new("database.db")
  db.type_translation = true
  db.results_as_hash = true

  use Rack::Auth::Basic, "Restricted Area" do |username, password|
	    [username, password] == ['admin', 'admin']
  end

  get '/' do
    haml :admin, :layout => :admin_layout
  end
  get '/hinnasto' do
    @tuotetyypit = db.execute("select id, nimi, taytteet from tuotetyyppi")
    @tuotetyypit.each do |tuotetyyppi|
      tuotetyyppi['tuotteet'] = db.execute("select * from tuote where tuotetyyppi_id = ?;",tuotetyyppi['id'])
      if tuotetyyppi['taytteet']==true
        tuotetyyppi['tuotteet'].each do |tuote|
          tuote['taytteet'] = db.execute("select tayte.nimi from tayte_tuote tt, tayte where tt.tuote_id = ? and tt.tayte_id=tayte.id;", tuote['id'])
        end
      end
    end
    @taytteet = db.execute("select id, nimi from tayte;")
    @taytteet.unshift({'nimi'=>'Ei taytetta'})

	@listat = db.execute("select * from ruokalista;")
    haml :admin_hinnasto, :layout => :admin_layout
  end
  get '/tilaukset' do
    haml :admin_tilaukset, :layout => :admin_layout
  end
  get '/tuote' do
    @tuotetyypit = db.execute("select * from tuotetyyppi;")
    haml :admin_tuote, :layout => :admin_layout
  end
  get '/lista' do
    haml :admin_lista, :layout => :admin_layout
  end
  get '/lista' do
    haml :admin_lista, :layout => :admin_layout
  end
  get '/lista_tuotteet/:lista' do
	  @lista = db.get_first_row("select * from ruokalista where id=?;", params[:lista])
	  @tuotteet = db.execute("select * from tuote;")
	  lista_jasenet = db.execute("select * from lista_jasen where ruokalista_id=?", params[:lista])
      @tuotteet.each do |tuote|
        lista_jasenet.each do |lista_jasen|
          if tuote['id']==lista_jasen['tuote_id']
            tuote['maaritelty']=true
			tuote['saatavilla']=lista_jasen['saatavilla']
			tuote['hinta']=lista_jasen['hinta']
          end
        end
      end
	  haml :admin_lista_tuotteet, :layout => :admin_layout
  end
  get '/lista/delete/:lista' do
    db.execute("delete from ruokalista where id=?;", params[:lista])
	redirect '/admin/hinnasto'
  end
  
  post '/tuote' do
    tuotetyyppi = db.execute("select id from tuotetyyppi where nimi=?;", params[:tuotetyyppi])[0]['id'];
    db.execute("insert into tuote(nimi, kuvaus, tuotetyyppi_id) values(?,?,?);",params[:nimi],params[:kuvaus], tuotetyyppi)
    redirect '/admin/hinnasto'
  end
  post '/lista' do
    db.execute("insert into ruokalista(nimi, prioriteetti, kuvaus, alku, loppu) values(?,?,?,?,?);", params[:nimi], params[:prioriteetti], params[:kuvaus], params[:alku], params[:loppu])
	redirect '/admin/hinnasto'
  end
  post '/taytteet/:tuote' do
    db.execute("delete from tayte_tuote where tuote_id=?;", params[:tuote])
    for i in (1..4) do
      tayte = params["tayte#{i}".to_sym]
      if tayte != 'Ei taytetta'
        tayte_id = db.get_first_value("select id from tayte where nimi=?",tayte)
        db.execute("insert into tayte_tuote(tayte_id, tuote_id) values(?,?)",tayte_id, params[:tuote])
      end
    end
    redirect '/admin/hinnasto'
  end
  post '/lista_tuotteet/:lista' do
	db.execute("delete from lista_jasen where ruokalista_id=?",params[:lista])
	tuotteet = db.execute("select * from tuote;")
    params[:tuotteet].each do |key, value|
      if value['maaritelty']
		saatavilla = value['saatavilla']?'t':'f'
        db.execute("insert into lista_jasen(ruokalista_id, tuote_id, saatavilla, hinta) values(?,?,?,?);", params[:lista], key, saatavilla, value['hinta'])
      end
    end
    redirect '/admin/hinnasto'
  end

end
