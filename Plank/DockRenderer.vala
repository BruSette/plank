//  
//  Copyright (C) 2011 Robert Dyer
// 
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
// 
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
// 
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
// 

using Cairo;
using Gdk;
using Gtk;

using Plank.Items;
using Plank.Services.Drawing;

namespace Plank
{
	public class DockRenderer : GLib.Object
	{
		public signal void render_needed ();
		
		DockWindow window;
		
		PlankSurface background_buffer;
		PlankSurface main_buffer;
		PlankSurface indicator_buffer;
		PlankSurface urgent_indicator_buffer;
		
		public int DockWidth {
			get { return (int) window.Items.Items.length () * (ItemPadding+ Prefs.IconSize) + 2 * DockPadding; }
		}
		
		public int DockHeight {
			get { return IndicatorSize / 2 + DockPadding + (int) (Prefs.Zoom * Prefs.IconSize); }
		}
		
		int VisibleDockHeight {
			get { return IndicatorSize / 2 + DockPadding + Prefs.IconSize; }
		}
		
		int IndicatorSize {
			get { return 5 * DockPadding; }
		}
		
		int DockPadding {
			get { return (int) (0.1 * Prefs.IconSize); }
		}
		
		int ItemPadding {
			get { return DockPadding; }
		}
		
		int UrgentHueShift {
			get { return 150; }
		}
		
		DockPreferences Prefs {
			get { return window.Prefs; }
		}
		
		ThemeRenderer theme { get; set; }
		
		public DockRenderer (DockWindow window)
		{
			this.window = window;
			theme = new ThemeRenderer ();
			theme.BottomRoundness = 0;
			window.notify["HoveredItem"].connect (animation_state_changed);
			Prefs.notify.connect (reset_buffers);
		}
		
		void animation_state_changed ()
		{
			render_needed ();
		}
		
		public void reset_buffers ()
		{
			main_buffer = null;
			background_buffer = null;
			
			render_needed ();
		}
		
		public Gdk.Rectangle item_region (DockItem item)
		{
			Gdk.Rectangle rect = Gdk.Rectangle ();
			
			rect.x = DockPadding + item.Position * (ItemPadding + Prefs.IconSize);
			rect.y = DockHeight - VisibleDockHeight;
			rect.width = Prefs.IconSize + ItemPadding;
			rect.height = VisibleDockHeight;
			
			return rect;
		}
		
		public void draw_dock (Context cr)
		{
			if (main_buffer != null && (main_buffer.Height != DockHeight || main_buffer.Width != DockWidth))
				reset_buffers ();
			
			if (main_buffer == null)
				main_buffer = new PlankSurface.with_surface (DockWidth, DockHeight, cr.get_target ());
			
			main_buffer.Clear ();
			
			draw_dock_background (main_buffer);
			
			foreach (DockItem item in window.Items.Items)
				draw_item (main_buffer, item);
			
			cr.set_operator (Operator.SOURCE);
			cr.set_source_surface (main_buffer.Internal, 0, 0);
			cr.paint ();
		}
		
		void draw_dock_background (PlankSurface surface)
		{
			if (background_buffer == null) {
				background_buffer = new PlankSurface.with_plank_surface (surface.Width, VisibleDockHeight, surface);
				
				theme.draw_background (background_buffer);
			}
			
			surface.Context.set_source_surface (background_buffer.Internal, 0, surface.Height - VisibleDockHeight);
			surface.Context.paint ();
		}
		
		void draw_item (PlankSurface surface, DockItem item)
		{
			PlankSurface icon_surface = new PlankSurface.with_plank_surface (Prefs.IconSize, Prefs.IconSize, main_buffer);
			
			Pixbuf pbuf = Drawing.load_pixbuf (item.Icon, Prefs.IconSize);
			cairo_set_source_pixbuf (icon_surface.Context, pbuf, 0, 0);
			icon_surface.Context.paint ();
			
			var lighten = 0.0;
			var darken = 0.0;
			
			if (window.HoveredItem == item && !Prefs.zoom_enabled ())
				lighten = 0.2;
			
			if (lighten > 0) {
				icon_surface.Context.set_operator (Cairo.Operator.ADD);
				icon_surface.Context.paint_with_alpha (lighten);
				icon_surface.Context.set_operator (Cairo.Operator.OVER);
			}
			
			if (darken > 0) {
				icon_surface.Context.rectangle (0, 0, Prefs.IconSize, Prefs.IconSize);
				icon_surface.Context.set_source_rgba (0, 0, 0, darken);
				
				icon_surface.Context.set_operator (Cairo.Operator.ATOP);
				icon_surface.Context.fill ();
				icon_surface.Context.set_operator (Cairo.Operator.OVER);
			}
			
			Gdk.Rectangle rect = item_region (item);
			surface.Context.set_source_surface (icon_surface.Internal, rect.x + ItemPadding / 2, rect.y + DockPadding);
			surface.Context.paint ();
			
			// draw indicators
			if (item.Indicator != IndicatorState.NONE) {
				if (indicator_buffer == null)
					create_normal_indicator ();
				if (urgent_indicator_buffer == null)
					create_urgent_indicator ();
				
				var indicator = (item.State & ItemState.URGENT) != 0 ? urgent_indicator_buffer : indicator_buffer;
				
				if (item.Indicator == IndicatorState.SINGLE) {
					surface.Context.set_source_surface (indicator.Internal, rect.x + ItemPadding / 2 + rect.width / 2 - indicator.Width / 2, DockHeight - indicator.Height / 2 - 1);
					surface.Context.paint ();
				} else {
					surface.Context.set_source_surface (indicator.Internal, rect.x + ItemPadding / 2 + rect.width / 2 - indicator.Width / 2 - 3, DockHeight - indicator.Height / 2 - 1);
					surface.Context.paint ();
					surface.Context.set_source_surface (indicator.Internal, rect.x + ItemPadding / 2 + rect.width / 2 - indicator.Width / 2 + 3, DockHeight - indicator.Height / 2 - 1);
					surface.Context.paint ();
				}
			}
		}
		
		void create_normal_indicator ()
		{
			var color = window.get_style ().bg [StateType.SELECTED];
			// TODO implement these
			//color = Drawing.set_min_value (color, 90);
			//color = Drawing.set_min_sat (color, 0.4);
			var r = color.red / (double) uint16.MAX;
			var g = color.green / (double) uint16.MAX;
			var b = color.blue / (double) uint16.MAX;
			indicator_buffer = create_indicator (IndicatorSize, r, g, b);
		}
		
		void create_urgent_indicator ()
		{
			var color = window.get_style ().bg [StateType.SELECTED];
			// TODO implement these
			//color = Drawing.set_min_value (color, 90);
			//color = Drawing.add_hue (color, UrgentHueShift);
			//color = Drawing.set_sat (color, 1);
			var r = color.red / (double) uint16.MAX;
			var g = color.green / (double) uint16.MAX;
			var b = color.blue / (double) uint16.MAX;
			urgent_indicator_buffer = create_indicator (IndicatorSize, r, g, b);
		}
		
		PlankSurface create_indicator (int size, double r, double g, double b)
		{
			PlankSurface surface = new PlankSurface.with_plank_surface (size, size, background_buffer);
			surface.Clear ();

			var cr = surface.Context;
			
			var x = size / 2;
			var y = x;
			
			cr.move_to (x, y);
			cr.arc (x, y, size / 2, 0, Math.PI * 2);
			
			var rg = new Pattern.radial (x, y, 0, x, y, size / 2);
			rg.add_color_stop_rgba (0, 1, 1, 1, 1);
			rg.add_color_stop_rgba (0.1, r, g, b, 1);
			rg.add_color_stop_rgba (0.2, r, g, b, 0.6);
			rg.add_color_stop_rgba (0.25, r, g, b, 0.25);
			rg.add_color_stop_rgba (0.5, r, g, b, 0.15);
			rg.add_color_stop_rgba (1.0, r, g, b, 0.0);
			
			cr.set_source (rg);
			cr.fill ();
			
			return surface;
		}
	}
}
