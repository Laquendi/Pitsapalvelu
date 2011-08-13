require './pitsapalvelu_julkinen'
require './pitsapalvelu_admin'

map "/" do
  run Pitsapalvelu_julkinen
end
map "/admin" do
  run Pitsapalvelu_admin
end
