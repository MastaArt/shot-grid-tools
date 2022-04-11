macroScript SG_T
Buttontext: "ShotGrid Tools"
category:"[3DGROUND]"
toolTip:"ShotGrid Tools"
Icon:#("UVWUnwrapView", 15)
(
	on execute do
	(
		szScript =  @"S:\00_Scripts\ShotGrid Tools.ms.ms"
		try(fileIn(szScript)) catch(messageBox "Script not found! Download WayFair Setup Tools again!" title: "Warning!")
	)
)

fn addQuadMenuButton macro cat txt remove: false =
(
	quadMenu = menuMan.getViewportRightClickMenu #nonePressed
	theMenu = quadMenu.getMenu 1

	fn findMenuItem theMenu menuName =
	(
		for i in 1 to theMenu.numItems() where (theMenu.getItem i).getTitle() == menuName do return i
		return 0
	)

	fn unregisterMenuItem theMenu menuName =
	(	
		try
		(
			for i in 1 to theMenu.numItems() do
			(
				if((theMenu.getItem i).getTitle() == menuName) do
				(
					theMenu.removeItemByPosition i 	

					if((theMenu.getItem (i - 1)).getIsSeparator()) do theMenu.removeItemByPosition (i - 1)
				)
			)
		)catch()
	)

	item = try(findMenuItem theMenu "Select &Similar")catch(6)

	unregisterMenuItem theMenu txt
	
	if(not remove) do
	(
		quadItem = menuMan.createActionItem macro (cat)
		
		theMenu.addItem quadItem (item += 1)
	)
		
	menuMan.updateMenuBar()
)

addQuadMenuButton "SG_T" "[3DGROUND]" "ShotGrid Tools" remove: true
addQuadMenuButton "SG_T" "[3DGROUND]" "ShotGrid Tools" remove: false

szScript =  @"S:\00_Scripts\ShotGrid Tools.ms.ms"
try(fileIn(szScript)) catch()