/datum/subsystem/vote
	var/crew_transfer_vote_time = null

/datum/subsystem/vote/get_result()
	//get the highest number of votes
	var/greatest_votes = 0
	var/total_votes = 0
	for(var/option in choices)
		var/votes = choices[option]
		total_votes += votes
		if(votes > greatest_votes)
			greatest_votes = votes
	//default-vote for everyone who didn't vote
	if(!config.vote_no_default && choices.len)
		var/list/non_voters = directory.Copy()
		non_voters -= voted
		for (var/non_voter_ckey in non_voters)
			var/client/C = non_voters[non_voter_ckey]
			if (!C || C.is_afk())
				non_voters -= non_voter_ckey
		if(non_voters.len > 0)
			if(mode == "transfer")
				choices["Continue Playing"] += non_voters.len
				if(choices["Continue Playing"] >= greatest_votes)
					greatest_votes = choices["Continue Playing"]
			if(mode == "restart")
				choices["Continue Playing"] += non_voters.len
				if(choices["Continue Playing"] >= greatest_votes)
					greatest_votes = choices["Continue Playing"]
			else if(mode == "gamemode")
				if(master_mode in choices)
					choices[master_mode] += non_voters.len
					if(choices[master_mode] >= greatest_votes)
						greatest_votes = choices[master_mode]
	//get all options with that many votes and return them in a list
	. = list()
	if(greatest_votes)
		for(var/option in choices)
			if(choices[option] == greatest_votes)
				. += option
	return .

/datum/subsystem/vote/result()
	. = announce_result()
	var/restart = 0
	var/transfer = 0
	if(.)
		switch(mode)
			if("restart")
				if(. == "Restart Round")
					restart = 1
			if("transfer")
				if(. == "Crew Transfer")
					transfer = 1
			if("gamemode")
				if(master_mode != .)
					world.save_mode(.)
					if(ticker && ticker.mode)
						restart = 1
					else
						master_mode = .
	if(restart)
		var/active_admins = 0
		for(var/client/C in admins)
			if(!C.is_afk() && check_rights_for(C, R_SERVER))
				active_admins = 1
				break
		if(!active_admins)
			world.Reboot("Restart vote successful.", "end_error", "restart vote")
		else
			world << "<span style='boldannounce'>Notice:Restart vote will not restart the server automatically because there are active admins on.</span>"
			message_admins("A restart vote has passed, but there are active admins on with +server, so it has been canceled. If you wish, you may restart the server.")

	if(transfer)
		world.Reboot("Restart vote successful.", "end_error", "restart vote")
		//TODO:CREW TRANSFER
		//SSshuttle.requestTransfer()
		//do some checks and start the crew transfer
	return .

/datum/subsystem/vote/initiate_vote(vote_type, initiator_key)
	if(!mode)
		if(started_time)
			var/next_allowed_time = (started_time + config.vote_delay)
			if(mode)
				usr << "<span class='warning'>There is already a vote in progress! please wait for it to finish.</span>"
				return 0

			var/admin = FALSE
			var/ckey = ckey(initiator_key)
			if((admin_datums[ckey]) || (ckey in deadmins))
				admin = TRUE

			if(next_allowed_time > world.time && !admin)
				usr << "<span class='warning'>A vote was initiated recently, you must wait roughly [(next_allowed_time-world.time)/10] seconds before a new vote can be started!</span>"
				return 0

		reset()
		switch(vote_type)
			if("transfer")
				//crew_transfer_vote_time =
				choices.Add("Crew Transfer","Continue Playing")
			if("restart")
				choices.Add("Restart Round","Continue Playing")
			if("gamemode")
				choices.Add(config.votable_modes)
			if("custom")
				question = stripped_input(usr,"What is the vote for?")
				if(!question)
					return 0
				for(var/i=1,i<=10,i++)
					var/option = capitalize(stripped_input(usr,"Please enter an option or hit cancel to finish"))
					if(!option || mode || !usr.client)
						break
					choices.Add(option)
			else
				return 0
		mode = vote_type
		initiator = initiator_key
		started_time = world.time
		var/text = "[capitalize(mode)] vote started by [initiator]."
		if(mode == "custom")
			text += "\n[question]"
		log_vote(text)
		world << "\n<font color='purple'><b>[text]</b>\nType <b>vote</b> or click <a href='?src=\ref[src]'>here</a> to place your votes.\nYou have [config.vote_period/10] seconds to vote.</font>"
		time_remaining = round(config.vote_period/10)
		for(var/c in clients)
			var/client/C = c
			var/datum/action/vote/V = new
			if(question)
				V.name = "Vote: [question]"
			V.Grant(C.mob)
			generated_actions += V
		return 1
	return 0

/datum/subsystem/vote/interface(client/C)
	if(!C)
		return
	var/admin = 0
	var/trialmin = 0
	if(C.holder)
		admin = 1
		if(check_rights_for(C, R_ADMIN))
			trialmin = 1
	voting |= C

	if(mode)
		if(question)
			. += "<h2>Vote: '[question]'</h2>"
		else
			. += "<h2>Vote: [capitalize(mode)]</h2>"
		. += "Time Left: [time_remaining] s<hr><ul>"
		for(var/i=1,i<=choices.len,i++)
			var/votes = choices[choices[i]]
			if(!votes)
				votes = 0
			. += "<li><a href='?src=\ref[src];vote=[i]'>[choices[i]]</a> ([votes] votes)</li>"
		. += "</ul><hr>"
		if(admin)
			. += "(<a href='?src=\ref[src];vote=cancel'>Cancel Vote</a>) "
	else
		. += "<h2>Start a vote:</h2><hr><ul><li>"
		//restart
		if(trialmin || config.allow_vote_restart)
			. += "<a href='?src=\ref[src];vote=restart'>Restart</a>"
		else
			. += "<font color='grey'>Restart (Disallowed)</font>"
		if(trialmin)
			. += "\t(<a href='?src=\ref[src];vote=toggle_restart'>[config.allow_vote_restart?"Allowed":"Disallowed"]</a>)"
		. += "</li><li>"
				//crew transfer
		. += "<a href='?src=\ref[src];vote=transfer'>Crew Transfer</a><br>"
		//gamemode
		if(trialmin || config.allow_vote_mode)
			. += "<a href='?src=\ref[src];vote=gamemode'>GameMode</a>"
		else
			. += "<font color='grey'>GameMode (Disallowed)</font>"
		if(trialmin)
			. += "\t(<a href='?src=\ref[src];vote=toggle_gamemode'>[config.allow_vote_mode?"Allowed":"Disallowed"]</a>)"

		. += "</li>"
		//custom
		if(trialmin)
			. += "<li><a href='?src=\ref[src];vote=custom'>Custom</a></li>"
		. += "</ul><hr>"
	. += "<a href='?src=\ref[src];vote=close' style='position:absolute;right:50px'>Close</a>"
	return .


/datum/subsystem/vote/Topic(href,href_list[],hsrc)
	if(!usr || !usr.client)
		return	//not necessary but meh...just in-case somebody does something stupid
	switch(href_list["vote"])
		if("close")
			voting -= usr.client
			usr << browse(null, "window=vote")
			return
		if("cancel")
			if(usr.client.holder)
				reset()
		if("toggle_restart")
			if(usr.client.holder)
				config.allow_vote_restart = !config.allow_vote_restart
		if("toggle_gamemode")
			if(usr.client.holder)
				config.allow_vote_mode = !config.allow_vote_mode
		if("transfer")
			initiate_vote("transfer",usr.key)
		if("restart")
			if(config.allow_vote_restart || usr.client.holder)
				initiate_vote("restart",usr.key)
		if("gamemode")
			if(config.allow_vote_mode || usr.client.holder)
				initiate_vote("gamemode",usr.key)
		if("custom")
			if(usr.client.holder)
				initiate_vote("custom",usr.key)
		else
			submit_vote(round(text2num(href_list["vote"])))
	usr.vote()

/datum/subsystem/vote/remove_action_buttons()
	for(var/v in generated_actions)
		var/datum/action/vote/V = v
		if(!QDELETED(V))
			V.Remove(V.owner)
	generated_actions = list()

/datum/subsystem/vote/proc/autogamemode()
	initiate_vote("gamemode","the server")