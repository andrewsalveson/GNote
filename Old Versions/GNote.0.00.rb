GNOTE_URL = 'http://localhost/GNote.php'

module GNote

class GNoteObserver < Sketchup::EntityObserver
	def initialize(id)
		@id = id
	end
	def onEraseEntity(entity)
		puts "note #{@id} has been erased"
		$gnote_control.forget_note(@id)
	end
	def onChangeEntity(entity)
		puts "notes #{@id} has been changed"
		$gnote_control.update_location(@id)
	end
end

class Note
	attr_accessor :origin,:data
	def initialize(origin)
		@origin = origin
	end

end

class Control
	attr_accessor :dialog,:username,:password
	def initialize
		m = Sketchup.active_model
		create_if_empty = true
		@d = m.attribute_dictionary "GNote", create_if_empty
		self.add_dialog
		if(@d['username'] == nil or @d['password'] == nil)
			self.log_in 
		else
			@username = @d['username']
			@password = @d['password']
		end
		@note_dialogs = Hash.new #container for note dialogs
		@notes = Hash.new #container for notes
		@observers = Hash.new #container for note observers
		#load note definition
		@path = File.dirname(__FILE__) + "/GNote/"
		if !@note_definition = m.definitions["GNote"]
			@note_definition = m.definitions.load(@path + 'GNote.skp')
		end
		
	end
	
	def Control.add_note_container(entities)
		container = entities.add_group
		container.set_attribute "GNote", "object_type", "container"
		subgroup = container.entities.add_group
		radius = 10
		3.times do |i|
			point = [0,0,0]
			[-1,1].each do |d|
				point[i] = d * radius
				puts point.join(',')
				subgroup.entities.add_line Geom::Point3d.new(0,0,0), Geom::Point3d.new(point)
			end
		end
		return container
	end
	
	def update_location(id)
	
	
	end
	
	def forget_note(id)
		puts "forgetting note #{id}"
		@notes[id] = nil
		@observers[id] = nil
	end
	
	def add_dialog
		#construct web dialog
		scrollable = true
		width = 225
		height = 400
		from_left = 600
		@dialog = UI::WebDialog.new("GNote Control Panel",scrollable,"GNote Control Panel",width,height,from_left)
		
		#add actions to dialog
		@dialog.add_action_callback("call_ruby") do |web_dialog,action_name|
			puts "received call from web dialog: call_ruby@#{action_name}"
			case action_name
				when "log_in"
					self.log_in
				when "log_out"
					self.log_out
			end
		end
		@dialog.add_action_callback("set_password_hash") do |web_dialog,password|
			puts "received password hash #{password} from dialog"
			@password = password
		end
		@dialog.add_action_callback("add_note") do |web_dialog,note|
			# "notes|2352|23.53|84.52|272.7" <-- note looks like this
			puts "reveived add_note command from dialog: #{note}"
			args = note.split('|')
			table = args[0]
			case table
				when "notes"
					t,id,lat,long,x,y,z = args
					self.add_note(id,x,y,z)
				when "sets"
					t,id,name = args
				when "set_data"
					t,id,read,write,delete = args
			end
		end
		
		#set dialog path and load dialog
		url = GNOTE_URL + "?application_type=Sketchup" #for local testing
		if(@username == nil or @password == nil)
			@dialog.set_url(url)
		else
			@dialog.set_url(GNOTE_URL + "?application_type=Sketchup&username=#{@username}&password=#{@password}")
		end
		puts "add_dialog: showing pane"
		@dialog.show()
	end

	def upload_note(x,y,z)
		data = "lat=#{}&long=#{}&x=#{x}&y=#{y}&z=#{z}"
		@dialog.post_url(@base_url + "?application_type=Sketchup&username=#{@username}&password=#{@password}",data)
	
	end
	
	def log_in
		prompts = ['username','password']
		username,password = UI.inputbox(prompts)
		@dialog.execute_script("tell_ruby_password_hash('#{password}')")
		#UI.messagebox("password: #{@password}")
		@d['username'] = @username = username
		@d['password'] = @password
		@dialog.set_url(GNOTE_URL + "?application_type=Sketchup&username=#{@username}&password=#{@password}")
		@dialog.show()
	end

	def move_note(id,x,y,z)
		@dialog.execute_script("adjustNoteFromSketchup('#{id}',#{x},#{y},#{z})")
	
	end
	
	def log_out
		puts "resetting dialog . . ."
		@d['username'] = @username = @d['password'] = @password = nil
		@dialog.set_url(GNOTE_URL + "?application_type=Sketchup")
		@dialog.show()
	end
	
	def add_note_dialog(id)
	if @note_dialogs[id] == nil
		keys = {
			:dialog_title => "GNote",
			:scrollable => false,
			:preferences_key => "GNote#{id}",
			:height => 200,
			:width => 200,
			:left => 150,
			:top => 150,
			:resizable => true,
			:mac_only_use_nswindow => true
		}
		@note_dialogs[id] = UI::WebDialog.new("GNote",false,"GNote#{id}") #title, scrollable, registry name, width, height, from left

		@note_dialogs[id].set_url(GNOTE_URL + "?view=note&id=#{id}&username=#{@username}&password=#{@password}")
	end
	@note_dialogs[id].show()
end
	
	def add_note(id,x,y,z)
		if @notes[id] != nil
			puts "note #{id} already present in model"
			return false
		end
		pt = Geom::Point3d.new(x.to_f,y.to_f,z.to_f)
		@notes[id] = Sketchup.active_model.entities.add_instance(@note_definition,pt)
		@notes[id].set_attribute('GNote','type','note')
		@notes[id].set_attribute('GNote','id',id)
		@observers[id] = @notes[id].add_observer GNoteObserver.new(id)
	end
end

def GNote.is_note
	#puts "checking to see if is note . . ."
	return false if not s = Sketchup.active_model.selection[0]
	return false if not s.get_attribute("GNote","type")
	puts "selection is GNote!"
	true
end

def GNote.show_note
	s = Sketchup.active_model.selection[0]
	id = s.get_attribute("GNote","id")
	$gnote_control.add_note_dialog(id)
end



end

if not file_loaded? __FILE__
	tools = UI.menu "Tools"
	tools.add_item("Launch Gnote") do
		$gnote_control = GNote::Control.new
	end

    UI.add_context_menu_handler do |menu|
        if( GNote.is_note )
            menu.add_separator
            menu.add_item("Show Note") { GNote.show_note }
        end
    end
	
	
	file_loaded(__FILE__)
end